"""Even G2 Debug Bridge用のエンジン非依存モッククライアント。

Unity Editorを起動せず、サーバーとEven Hubフロントエンドの統合テストに使用する。
"""

from __future__ import annotations

import argparse
import asyncio
import json
from datetime import datetime

import websockets

PROTOCOL_VERSION = 1
DEFAULT_URL = "ws://localhost:8766"

SEQUENTIAL_LOGS = [
    {"level": "Log", "message": "プレイヤーがエリア A に入りました"},
    {"level": "Log", "message": "FPS: 60 | メモリ使用量: 128MB"},
    {"level": "Warning", "message": "アイテムのスポーン数が上限に近づいています (48/50)"},
    {"level": "Error", "message": "NullReferenceException: EnemyController.Update() at line 42"},
]

LEVEL_LOGS = [
    {"level": "Log", "message": "これは通常ログ (Log) です"},
    {"level": "Warning", "message": "これは警告ログ (Warning) です"},
    {"level": "Error", "message": "これはエラーログ (Error) です"},
    {"level": "Exception", "message": "これは例外ログ (Exception) です"},
]

LONG_MESSAGE = (
    "長いメッセージのテスト: "
    + "あ" * 350
    + " | ステージ情報: ステージ1-2, エリアB, セクション3 | "
    + "B" * 400
)


def make_log_payload(level: str, message: str) -> str:
    return json.dumps(
        {
            "type": "log",
            "level": level,
            "message": message,
            "timestamp": datetime.now().strftime("%H:%M:%S"),
            "tag": "[Even]",
            "protocol_version": PROTOCOL_VERSION,
        },
        ensure_ascii=False,
    )


async def send_entries(websocket, entries: list[dict[str, str]], interval: float) -> None:
    for entry in entries:
        await websocket.send(make_log_payload(entry["level"], entry["message"]))
        print(f"  -> [{entry['level']}] {entry['message']}")
        if interval > 0:
            await asyncio.sleep(interval)


async def run_test(url: str, mode: str, interval: float, count: int) -> None:
    print(f"[mock] 接続先: {url}")
    async with websockets.connect(url) as websocket:
        await websocket.send(json.dumps({"type": "engine", "protocol_version": PROTOCOL_VERSION}))
        hello = json.loads(await websocket.recv())
        if hello.get("type") != "connected":
            raise RuntimeError(f"Unexpected server response: {hello}")

        print(f"[mock] {mode} モードを開始します")
        if mode == "sequential":
            await send_entries(websocket, SEQUENTIAL_LOGS, interval)
        elif mode == "levels":
            await send_entries(websocket, LEVEL_LOGS, interval)
        elif mode == "rapid":
            entries = [
                {"level": "Log", "message": f"高頻度テスト {index:02d}/{count:02d}"}
                for index in range(1, count + 1)
            ]
            await send_entries(websocket, entries, interval)
        elif mode == "long":
            await send_entries(websocket, [{"level": "Log", "message": LONG_MESSAGE}], 0)

        print("[mock] 送信完了")
        await asyncio.sleep(0.5)


def main() -> None:
    parser = argparse.ArgumentParser(description="Even G2 Debug Bridge mock engine")
    parser.add_argument("--url", default=DEFAULT_URL, help="サーバーのWebSocket URL")
    parser.add_argument(
        "--mode",
        choices=["sequential", "levels", "rapid", "long"],
        default="sequential",
        help="実行するテストシナリオ",
    )
    parser.add_argument("--interval", type=float, default=None, help="各ログ間隔（秒）")
    parser.add_argument("--count", type=int, default=20, help="rapidモードのログ件数")
    args = parser.parse_args()

    defaults = {"sequential": 1.0, "levels": 1.0, "rapid": 0.05, "long": 0.0}
    interval = defaults[args.mode] if args.interval is None else max(args.interval, 0)
    asyncio.run(run_test(args.url, args.mode, interval, max(args.count, 1)))


if __name__ == "__main__":
    main()
