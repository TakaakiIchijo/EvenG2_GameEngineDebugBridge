class_name DungeonItem
extends RefCounted

enum Kind {
    AMMO_BOX,
    MED_AMPOULE,
    KEY_FRAGMENT,
    DATA_CASSETTE,
    POWER_CELL,
    ALTAR_CORE,
}

var id: int
var kind: Kind
var cell: Vector2i
var is_collected := false


func _init(item_id: int, item_kind: Kind, item_cell: Vector2i) -> void:
    id = item_id
    kind = item_kind
    cell = item_cell


func display_name() -> String:
    match kind:
        Kind.AMMO_BOX:
            return "弾薬箱"
        Kind.MED_AMPOULE:
            return "医療アンプル"
        Kind.KEY_FRAGMENT:
            return "鍵の欠片"
        Kind.DATA_CASSETTE:
            return "データカセット"
        Kind.POWER_CELL:
            return "電力セル"
        Kind.ALTAR_CORE:
            return "祭壇コア"
    return "不明な回収物"


func accent_color() -> Color:
    match kind:
        Kind.AMMO_BOX:
            return Color("e3a23e")
        Kind.MED_AMPOULE:
            return Color("78b96c")
        Kind.KEY_FRAGMENT:
            return Color("82c5d9")
        Kind.DATA_CASSETTE:
            return Color("bc5c91")
        Kind.POWER_CELL:
            return Color("e06934")
        Kind.ALTAR_CORE:
            return Color("9b3e62")
    return Color.WHITE
