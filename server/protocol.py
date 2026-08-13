"""Even G2 Debug Bridge のエンジン非依存メッセージプロトコル。"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any

PROTOCOL_VERSION = 1
LOG_TAG = "[Even]"
LOG_LEVELS = {"Log", "Warning", "Error", "Exception"}
MAX_MESSAGE_CHARACTERS = 4096


@dataclass(frozen=True)
class LogEntry:
    """ゲームエンジンから受信し、Webアプリへ配信するログ。"""

    level: str
    message: str
    timestamp: str
    tag: str = LOG_TAG
    type: str = "log"
    protocol_version: int = PROTOCOL_VERSION

    def to_dict(self) -> dict[str, str | int]:
        return asdict(self)


def parse_client_hello(payload: Any) -> str | None:
    """最初のメッセージからクライアント種別を安全に取得する。"""

    if not isinstance(payload, dict):
        return None

    client_type = payload.get("type")
    return client_type if client_type in {"engine", "browser"} else None


def parse_log_entry(payload: Any) -> LogEntry | None:
    """エンジン側ログを正規化する。無効な入力は ``None`` を返す。"""

    if not isinstance(payload, dict) or payload.get("type") != "log":
        return None

    message = payload.get("message")
    if not isinstance(message, str) or not message.strip():
        return None

    level = payload.get("level", "Log")
    level = level if level in LOG_LEVELS else "Log"

    timestamp = payload.get("timestamp")
    if not isinstance(timestamp, str) or not timestamp:
        timestamp = datetime.now().strftime("%H:%M:%S")

    tag = payload.get("tag", LOG_TAG)
    tag = tag if isinstance(tag, str) else LOG_TAG

    return LogEntry(
        level=level,
        message=message[:MAX_MESSAGE_CHARACTERS],
        timestamp=timestamp[:32],
        tag=tag[:32],
    )


def make_status_payload(status: str, detail: str = "") -> dict[str, str | int]:
    """サーバー状態通知の共通形式を生成する。"""

    return {
        "type": "status",
        "status": status,
        "detail": detail,
        "protocol_version": PROTOCOL_VERSION,
    }


def make_hello_payload(client_type: str) -> dict[str, str | int]:
    """接続完了時の応答を生成する。"""

    return {
        "type": "connected",
        "client_type": client_type,
        "protocol_version": PROTOCOL_VERSION,
    }


def make_history_payload(entries: list[LogEntry]) -> dict[str, list[dict[str, str | int]] | str | int]:
    """接続直後にブラウザへ送る履歴ペイロードを生成する。"""

    return {
        "type": "history",
        "logs": [entry.to_dict() for entry in entries],
        "protocol_version": PROTOCOL_VERSION,
    }
