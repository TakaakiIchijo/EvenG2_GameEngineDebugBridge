"""Even G2 Debug Bridge のエンジン非依存メッセージプロトコル。"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any

PROTOCOL_VERSION = 1
LOG_TAG = "[Even]"
LOG_LEVELS = {"Log", "Warning", "Error", "Exception"}
MAX_MESSAGE_CHARACTERS = 4096
MAX_MINIMAP_SIDE = 31
MAX_MINIMAP_CELLS = MAX_MINIMAP_SIDE * MAX_MINIMAP_SIDE


@dataclass(frozen=True)
class MinimapState:
    """ゲームエンジンからWebアプリへ中継する探索ミニマップ状態。"""

    width: int
    height: int
    walls: str
    explored: str
    player_x: int
    player_y: int
    facing: int
    goal_x: int
    goal_y: int
    revision: int
    state: str
    type: str = "minimap"
    protocol_version: int = PROTOCOL_VERSION

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.type,
            "width": self.width,
            "height": self.height,
            "walls": self.walls,
            "explored": self.explored,
            "player": {"x": self.player_x, "y": self.player_y, "facing": self.facing},
            "goal": {"x": self.goal_x, "y": self.goal_y},
            "revision": self.revision,
            "state": self.state,
            "protocol_version": self.protocol_version,
        }


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


def parse_minimap_state(payload: Any) -> MinimapState | None:
    """エンジン側から届くミニマップ状態を検証して正規化する。"""

    if not isinstance(payload, dict) or payload.get("type") != "minimap":
        return None

    width = payload.get("width")
    height = payload.get("height")
    walls = payload.get("walls")
    explored = payload.get("explored")
    player = payload.get("player")
    goal = payload.get("goal")

    if not isinstance(width, int) or not isinstance(height, int):
        return None
    if width < 5 or height < 5 or width > MAX_MINIMAP_SIDE or height > MAX_MINIMAP_SIDE:
        return None
    expected_length = width * height
    if expected_length > MAX_MINIMAP_CELLS:
        return None
    if not isinstance(walls, str) or not isinstance(explored, str):
        return None
    if len(walls) != expected_length or len(explored) != expected_length:
        return None
    if set(walls) - {"0", "1"} or set(explored) - {"0", "1"}:
        return None
    if not isinstance(player, dict) or not isinstance(goal, dict):
        return None

    player_x = player.get("x")
    player_y = player.get("y")
    facing = player.get("facing", 0)
    goal_x = goal.get("x")
    goal_y = goal.get("y")
    if not all(isinstance(value, int) for value in (player_x, player_y, facing, goal_x, goal_y)):
        return None
    if not (0 <= player_x < width and 0 <= player_y < height and 0 <= goal_x < width and 0 <= goal_y < height):
        return None
    if facing not in {0, 1, 2, 3}:
        return None

    revision = payload.get("revision", 0)
    state = payload.get("state", "exploring")
    if not isinstance(revision, int) or revision < 0:
        return None
    if not isinstance(state, str) or not state or len(state) > 32:
        return None

    return MinimapState(
        width=width,
        height=height,
        walls=walls,
        explored=explored,
        player_x=player_x,
        player_y=player_y,
        facing=facing,
        goal_x=goal_x,
        goal_y=goal_y,
        revision=revision,
        state=state,
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


def make_minimap_payload(state: MinimapState) -> dict[str, Any]:
    """Webアプリへ送るミニマップの共通形式を生成する。"""

    return state.to_dict()


def make_history_payload(entries: list[LogEntry]) -> dict[str, list[dict[str, str | int]] | str | int]:
    """接続直後にブラウザへ送る履歴ペイロードを生成する。"""

    return {
        "type": "history",
        "logs": [entry.to_dict() for entry in entries],
        "protocol_version": PROTOCOL_VERSION,
    }
