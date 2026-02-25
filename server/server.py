"""
Even G2 Debug Bridge - ローカルサーバー
============================================
ゲームエンジン（Unity / Unreal / Godot など）から WebSocket 経由でログを受信し、
Even G2 Webアプリケーションにリアルタイムで配信するブリッジサーバー。

起動方法:
    pip install -r requirements.txt
    python server.py

環境変数 (省略可):
    HTTP_PORT  : HTTPサーバーのポート番号 (デフォルト: 8765)
    WS_PORT    : WebSocketサーバーのポート番号 (デフォルト: 8766)
"""

import asyncio
import json
import logging
import os
import socket
import threading
from collections import deque
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

import websockets

# ---------------------------------------------------------------------------
# 設定
# ---------------------------------------------------------------------------
HTTP_PORT = int(os.environ.get("HTTP_PORT", 8765))
WS_PORT = int(os.environ.get("WS_PORT", 8766))
LOG_BUFFER_SIZE = 50  # グラスに配信するログの最大保持件数
FRONTEND_DIR = Path(__file__).parent.parent / "frontend" / "dist"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 状態管理
# ---------------------------------------------------------------------------
# 受信したログのリングバッファ（最新 LOG_BUFFER_SIZE 件を保持）
log_buffer: deque[dict] = deque(maxlen=LOG_BUFFER_SIZE)

# 接続中の Even G2 Webアプリ（ブラウザ側）クライアント
browser_clients: set = set()

# 接続中のゲームエンジンクライアント
engine_clients: set = set()


def get_local_ip() -> str:
    """同一ネットワーク内からアクセス可能なローカルIPアドレスを取得する。"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"


# ---------------------------------------------------------------------------
# WebSocket ハンドラ (websockets v14+ 対応)
# ---------------------------------------------------------------------------
async def handle_connection(websocket) -> None:
    """
    接続してきたクライアントを種別に応じて振り分ける。

    ゲームエンジン側は接続直後に {"type": "engine"} を送信する。
    Even G2 Webアプリ側は接続直後に {"type": "browser"} を送信する。
    """
    client_type = "unknown"
    try:
        # 最初のメッセージで種別を判定
        first_msg_raw = await asyncio.wait_for(websocket.recv(), timeout=5.0)
        first_msg = json.loads(first_msg_raw)
        client_type = first_msg.get("type", "unknown")

        if client_type == "engine":
            await handle_engine_client(websocket)
        elif client_type == "browser":
            await handle_browser_client(websocket)
        else:
            logger.warning("不明なクライアント種別: %s", client_type)
    except asyncio.TimeoutError:
        logger.warning("クライアント種別の判定がタイムアウトしました")
    except websockets.exceptions.ConnectionClosed:
        pass
    except Exception as e:
        logger.error("接続処理エラー (%s): %s", client_type, e)


async def handle_engine_client(websocket) -> None:
    """
    ゲームエンジン（Unity / Unreal / Godot）からのログを受信する。
    受信したログはバッファに追加し、接続中のブラウザクライアントに配信する。
    """
    engine_clients.add(websocket)
    remote = websocket.remote_address
    logger.info("ゲームエンジン接続: %s", remote)

    # 接続確認レスポンスを返す
    await websocket.send(json.dumps({"type": "connected", "message": "Even G2 Debug Bridge に接続しました"}))

    try:
        async for message_raw in websocket:
            try:
                message = json.loads(message_raw)
                log_entry = {
                    "type": "log",
                    "level": message.get("level", "Log"),
                    "message": message.get("message", ""),
                    "timestamp": message.get("timestamp", ""),
                    "tag": message.get("tag", ""),
                }
                log_buffer.append(log_entry)
                logger.info("[Engine Log] [%s] %s", log_entry["level"], log_entry["message"])

                # 接続中のブラウザクライアントに即時配信
                if browser_clients:
                    payload = json.dumps(log_entry)
                    await asyncio.gather(
                        *[client.send(payload) for client in browser_clients],
                        return_exceptions=True,
                    )
            except json.JSONDecodeError:
                logger.warning("不正なJSONを受信: %s", message_raw)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        engine_clients.discard(websocket)
        logger.info("ゲームエンジン切断: %s", remote)


async def handle_browser_client(websocket) -> None:
    """
    Even G2 Webアプリ（ブラウザ）からの接続を管理する。
    接続時にバッファ内の既存ログを一括送信する。
    """
    browser_clients.add(websocket)
    remote = websocket.remote_address
    logger.info("ブラウザクライアント接続: %s", remote)

    try:
        # 接続時にバッファ内の既存ログを送信
        if log_buffer:
            history_payload = json.dumps({
                "type": "history",
                "logs": list(log_buffer),
            })
            await websocket.send(history_payload)

        # 接続を維持（ゲームエンジン側からのプッシュを待つ）
        await websocket.wait_closed()
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        browser_clients.discard(websocket)
        logger.info("ブラウザクライアント切断: %s", remote)


# ---------------------------------------------------------------------------
# HTTP サーバー（フロントエンドのホスティング）
# ---------------------------------------------------------------------------
class FrontendHandler(SimpleHTTPRequestHandler):
    """Even G2 Webアプリの静的ファイルを配信するHTTPハンドラ。"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(FRONTEND_DIR), **kwargs)

    def log_message(self, format, *args):
        logger.debug("HTTP: " + format, *args)

    def end_headers(self):
        # CORS ヘッダーを付与（同一ネットワーク内のスマートフォンからのアクセスを許可）
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def run_http_server() -> None:
    """HTTPサーバーを別スレッドで起動する。"""
    if not FRONTEND_DIR.exists():
        logger.warning(
            "フロントエンドのビルドディレクトリが見つかりません: %s\n"
            "frontend/ ディレクトリで `npm run build` を実行してください。",
            FRONTEND_DIR,
        )
        return

    server = HTTPServer(("0.0.0.0", HTTP_PORT), FrontendHandler)
    logger.info("HTTPサーバー起動: http://0.0.0.0:%d", HTTP_PORT)
    server.serve_forever()


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------
async def main() -> None:
    local_ip = get_local_ip()

    # HTTPサーバーを別スレッドで起動
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()

    # WebSocketサーバーを起動 (websockets v14+ の新API)
    async with websockets.serve(handle_connection, "0.0.0.0", WS_PORT):
        logger.info("=" * 60)
        logger.info("Even G2 Debug Bridge が起動しました")
        logger.info("=" * 60)
        logger.info("  WebSocket (ゲームエンジン/ブラウザ): ws://%s:%d", local_ip, WS_PORT)
        logger.info("  Even G2 Webアプリ (HTTP):           http://%s:%d", local_ip, HTTP_PORT)
        logger.info("")
        logger.info("  Unity Editorプラグインの接続先URL:")
        logger.info("    ws://%s:%d", local_ip, WS_PORT)
        logger.info("")
        logger.info("  スマートフォンのEven HubアプリでアクセスするURL:")
        logger.info("    http://%s:%d", local_ip, HTTP_PORT)
        logger.info("=" * 60)
        await asyncio.Future()  # サーバーを永続的に実行


if __name__ == "__main__":
    asyncio.run(main())
