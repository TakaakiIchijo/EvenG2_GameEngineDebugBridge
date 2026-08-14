"""Even G2 Debug Bridge のエンジン非依存ローカルブリッジサーバー。

ゲームエンジンは WebSocket でログを送信し、Even Hub Webアプリは同じ
WebSocket からログを受信する。HTTPサーバーはビルド済みフロントエンドを
同一LAN内のスマートフォンへ配信する。

環境変数:
    HTTP_PORT: HTTP配信ポート（既定: 8765）
    WS_PORT:   WebSocketポート（既定: 8766）
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import socket
import threading
from collections import deque
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from protocol import (
    LogEntry,
    MinimapState,
    make_hello_payload,
    make_history_payload,
    make_minimap_payload,
    make_status_payload,
    parse_client_hello,
    parse_log_entry,
    parse_minimap_state,
)

HTTP_PORT = int(os.environ.get("HTTP_PORT", "8765"))
WS_PORT = int(os.environ.get("WS_PORT", "8766"))
LOG_BUFFER_SIZE = 20
CLIENT_HELLO_TIMEOUT_SECONDS = 5
FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend" / "dist"

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("even_g2_debug_bridge")

log_buffer: deque[LogEntry] = deque(maxlen=LOG_BUFFER_SIZE)
latest_minimap: MinimapState | None = None
browser_clients: set[Any] = set()
engine_clients: set[Any] = set()


def get_local_ip() -> str:
    """同一LAN上の端末が到達できるローカルIPアドレスを取得する。"""

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return str(sock.getsockname()[0])
    except OSError:
        return "127.0.0.1"


async def send_json(connection: Any, payload: dict[str, Any]) -> None:
    """JSONペイロードを送信する。クライアントの切断は呼び出し側で処理する。"""

    await connection.send(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


async def broadcast_log(entry: LogEntry) -> None:
    """接続中のWebアプリへ正規化済みログを配信する。"""

    if not browser_clients:
        return

    payload = json.dumps(entry.to_dict(), ensure_ascii=False, separators=(",", ":"))
    recipients = tuple(browser_clients)
    results = await asyncio.gather(
        *(client.send(payload) for client in recipients),
        return_exceptions=True,
    )

    for client, result in zip(recipients, results):
        if isinstance(result, Exception):
            browser_clients.discard(client)
            logger.debug("切断済みWebアプリクライアントを除外しました: %s", result)


async def broadcast_minimap(state: MinimapState) -> None:
    """接続中のWebアプリへ検証済みの最新ミニマップを配信する。"""

    if not browser_clients:
        return

    payload = json.dumps(make_minimap_payload(state), ensure_ascii=False, separators=(",", ":"))
    recipients = tuple(browser_clients)
    results = await asyncio.gather(
        *(client.send(payload) for client in recipients),
        return_exceptions=True,
    )
    for client, result in zip(recipients, results):
        if isinstance(result, Exception):
            browser_clients.discard(client)
            logger.debug("切断済みWebアプリクライアントを除外しました: %s", result)


async def handle_engine_client(connection: Any) -> None:
    """ゲームエンジンから受信したログを検証・正規化してファンアウトする。"""

    engine_clients.add(connection)
    remote = connection.remote_address
    logger.info("ゲームエンジン接続: %s", remote)

    try:
        await send_json(connection, make_hello_payload("engine"))
        async for raw_message in connection:
            try:
                payload = json.loads(raw_message)
            except (json.JSONDecodeError, TypeError):
                logger.warning("不正なJSONを受信しました: %r", raw_message)
                await send_json(connection, make_status_payload("rejected", "invalid_json"))
                continue

            entry = parse_log_entry(payload)
            if entry is not None:
                log_buffer.append(entry)
                logger.info("[Engine Log] [%s] %s", entry.level, entry.message)
                await broadcast_log(entry)
                continue

            minimap = parse_minimap_state(payload)
            if minimap is not None:
                global latest_minimap
                latest_minimap = minimap
                logger.info("[Minimap] %dx%d revision=%d state=%s", minimap.width, minimap.height, minimap.revision, minimap.state)
                await broadcast_minimap(minimap)
                continue

            logger.warning("不正なエンジンペイロードを拒否しました: %r", payload)
            await send_json(connection, make_status_payload("rejected", "invalid_engine_payload"))
    except ConnectionClosed:
        pass
    finally:
        engine_clients.discard(connection)
        logger.info("ゲームエンジン切断: %s", remote)


async def handle_browser_client(connection: Any) -> None:
    """Even Hub Webアプリへ履歴と以後のリアルタイムログを提供する。"""

    browser_clients.add(connection)
    remote = connection.remote_address
    logger.info("Webアプリ接続: %s", remote)

    try:
        await send_json(connection, make_hello_payload("browser"))
        await send_json(connection, make_history_payload(list(log_buffer)))
        if latest_minimap is not None:
            await send_json(connection, make_minimap_payload(latest_minimap))
        await connection.wait_closed()
    except ConnectionClosed:
        pass
    finally:
        browser_clients.discard(connection)
        logger.info("Webアプリ切断: %s", remote)


async def handle_connection(connection: Any) -> None:
    """最初のメッセージに従い、エンジンまたはWebアプリとして接続を振り分ける。"""

    client_type = "unknown"
    try:
        raw_hello = await asyncio.wait_for(connection.recv(), timeout=CLIENT_HELLO_TIMEOUT_SECONDS)
        client_type = parse_client_hello(json.loads(raw_hello)) or "unknown"

        if client_type == "engine":
            await handle_engine_client(connection)
        elif client_type == "browser":
            await handle_browser_client(connection)
        else:
            logger.warning("不明なクライアント種別です: %s", client_type)
            await send_json(connection, make_status_payload("rejected", "unknown_client_type"))
            await connection.close(code=1008, reason="Unknown client type")
    except asyncio.TimeoutError:
        logger.warning("クライアント種別の判定がタイムアウトしました")
        await connection.close(code=1008, reason="Client hello timeout")
    except (json.JSONDecodeError, TypeError):
        logger.warning("接続時のクライアント宣言が不正です")
        await connection.close(code=1008, reason="Invalid client hello")
    except ConnectionClosed:
        pass
    except Exception:
        logger.exception("接続処理中に予期しないエラーが発生しました: %s", client_type)


class FrontendHandler(SimpleHTTPRequestHandler):
    """ビルド済みWebアプリとヘルスチェックを配信するHTTPハンドラ。"""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(FRONTEND_DIR), **kwargs)

    def log_message(self, format: str, *args: Any) -> None:
        logger.debug("HTTP: " + format, *args)

    def end_headers(self) -> None:
        # LAN内ローカル開発用。外部公開サーバーとして利用しないこと。
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.end_headers()

    def do_GET(self) -> None:
        if self.path == "/health":
            body = json.dumps(
                {
                    "status": "ok",
                    "browser_clients": len(browser_clients),
                    "engine_clients": len(engine_clients),
                    "buffered_logs": len(log_buffer),
                    "has_minimap": latest_minimap is not None,
                },
                ensure_ascii=False,
            ).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()


def run_http_server() -> None:
    """HTTPサーバーを別スレッドで起動する。"""

    if not FRONTEND_DIR.exists():
        logger.warning(
            "フロントエンドのビルドディレクトリがありません: %s\n"
            "frontend/ で `npm run build` を実行してから再起動してください。",
            FRONTEND_DIR,
        )
        return

    server = ThreadingHTTPServer(("0.0.0.0", HTTP_PORT), FrontendHandler)
    logger.info("HTTPサーバー起動: http://0.0.0.0:%d", HTTP_PORT)
    server.serve_forever()


async def main() -> None:
    """HTTP配信とWebSocketブリッジを開始する。"""

    local_ip = get_local_ip()
    threading.Thread(target=run_http_server, daemon=True).start()

    async with serve(handle_connection, "0.0.0.0", WS_PORT, origins=None):
        logger.info("=" * 60)
        logger.info("Even G2 Debug Bridge を起動しました")
        logger.info("WebSocket: ws://%s:%d", local_ip, WS_PORT)
        logger.info("Webアプリ:  http://%s:%d", local_ip, HTTP_PORT)
        logger.info("ヘルス確認:  http://%s:%d/health", local_ip, HTTP_PORT)
        logger.info("=" * 60)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
