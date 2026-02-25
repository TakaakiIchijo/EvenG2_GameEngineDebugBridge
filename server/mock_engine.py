"""
mock_engine.py
==============
Unity Editor（ゲームエンジン）が送信するログをシミュレートするモックスクリプト。
テスト用途のみ。本番環境では使用しない。

使い方:
    python mock_engine.py [--url ws://localhost:8766] [--mode <mode>]

モード:
    sequential  : 定義済みのテストログを順番に送信する（デフォルト）
    rapid       : 短い間隔で大量のログを送信し、更新速度をテストする
    levels      : Log / Warning / Error / Exception の全レベルを送信する
    long        : 900文字に近い長いメッセージを送信する
"""

import asyncio
import json
import argparse
from datetime import datetime
import websockets


# ---------------------------------------------------------------------------
# テストシナリオ定義
# ---------------------------------------------------------------------------

SEQUENTIAL_LOGS = [
    {"level": "Log",       "message": "プレイヤーがエリア A に入りました"},
    {"level": "Log",       "message": "FPS: 60 | メモリ使用量: 128MB"},
    {"level": "Warning",   "message": "アイテムのスポーン数が上限に近づいています (48/50)"},
    {"level": "Log",       "message": "チェックポイント到達: Stage 1-2"},
    {"level": "Error",     "message": "NullReferenceException: EnemyController.Update() at line 42"},
    {"level": "Log",       "message": "ボス戦開始 - HP: 1000 / ATK: 35"},
    {"level": "Warning",   "message": "ネットワーク遅延検出: 120ms"},
    {"level": "Log",       "message": "プレイヤーがクリアしました - タイム: 03:24.55"},
]

LEVELS_LOGS = [
    {"level": "Log",       "message": "これは通常ログ (Log) です"},
    {"level": "Warning",   "message": "これは警告ログ (Warning) です"},
    {"level": "Error",     "message": "これはエラーログ (Error) です"},
    {"level": "Exception", "message": "これは例外ログ (Exception) です"},
]

LONG_MESSAGE = (
    "長いメッセージのテスト: "
    + "A" * 200
    + " | ステージ情報: ステージ1-2, エリアB, セクション3 "
    + "B" * 200
    + " | プレイヤー座標: X=1234.56, Y=789.01, Z=-42.00 "
    + "C" * 200
    + " | 追加情報: テスト用の長文メッセージです。"
)

RAPID_MESSAGES = [
    f"ラピッドテスト: ログ #{i:03d} - タイムスタンプ {datetime.now().isoformat()}"
    for i in range(1, 11)
]


# ---------------------------------------------------------------------------
# 送信ロジック
# ---------------------------------------------------------------------------

def build_payload(level: str, message: str) -> str:
    return json.dumps({
        "type":      "log",
        "level":     level,
        "message":   message,
        "timestamp": datetime.now().strftime("%H:%M:%S"),
        "tag":       "[Even]",
    })


async def run_sequential(ws, interval: float = 2.5):
    print("[mock] sequential モード: テストログを順番に送信します")
    for entry in SEQUENTIAL_LOGS:
        payload = build_payload(entry["level"], entry["message"])
        await ws.send(payload)
        print(f"  -> [{entry['level']}] {entry['message']}")
        await asyncio.sleep(interval)


async def run_levels(ws, interval: float = 2.0):
    print("[mock] levels モード: 全レベルのログを送信します")
    for entry in LEVELS_LOGS:
        payload = build_payload(entry["level"], entry["message"])
        await ws.send(payload)
        print(f"  -> [{entry['level']}] {entry['message']}")
        await asyncio.sleep(interval)


async def run_rapid(ws, interval: float = 0.8):
    print("[mock] rapid モード: 高速でログを送信します")
    for msg in RAPID_MESSAGES:
        payload = build_payload("Log", msg)
        await ws.send(payload)
        print(f"  -> [Log] {msg}")
        await asyncio.sleep(interval)


async def run_long(ws):
    print("[mock] long モード: 長いメッセージを送信します")
    payload = build_payload("Log", LONG_MESSAGE)
    await ws.send(payload)
    print(f"  -> [Log] (長さ: {len(LONG_MESSAGE)} 文字)")


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

async def main(url: str, mode: str):
    print(f"[mock] サーバーに接続中: {url}")
    try:
        async with websockets.connect(url) as ws:
            # エンジンクライアントとして自己紹介
            await ws.send(json.dumps({"type": "engine"}))
            print("[mock] 接続完了。ログ送信を開始します...")
            await asyncio.sleep(0.5)

            if mode == "sequential":
                await run_sequential(ws)
            elif mode == "levels":
                await run_levels(ws)
            elif mode == "rapid":
                await run_rapid(ws)
            elif mode == "long":
                await run_long(ws)
            else:
                print(f"[mock] 不明なモード: {mode}")

            print("[mock] 全ログの送信が完了しました。")
            await asyncio.sleep(1.0)
    except ConnectionRefusedError:
        print(f"[mock] 接続拒否: サーバーが起動しているか確認してください ({url})")
    except Exception as e:
        print(f"[mock] エラー: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Even G2 Debug Bridge - モックエンジンクライアント")
    parser.add_argument("--url",  default="ws://localhost:8766", help="サーバーの WebSocket URL")
    parser.add_argument("--mode", default="sequential",
                        choices=["sequential", "levels", "rapid", "long"],
                        help="テストモード")
    args = parser.parse_args()
    asyncio.run(main(args.url, args.mode))
