class_name DungeonEnemy
extends RefCounted

## グリッドダンジョンの敵1体を表すデータモデル。

const DEFINITIONS := {
    "stalker": {"role": "minion", "name": "Stalker", "health": 34, "damage": 10, "armor": 0, "move": "pursue", "attack": "melee", "range": 1, "color": Color("d65b70")},
    "skirmisher": {"role": "minion", "name": "Skirmisher", "health": 26, "damage": 8, "armor": 0, "move": "keep_range", "attack": "ranged", "range": 3, "color": Color("ed9d5d")},
    "charger": {"role": "minion", "name": "Charger", "health": 42, "damage": 14, "armor": 1, "move": "charge", "attack": "melee", "range": 1, "color": Color("e8c45f")},
    "sentry": {"role": "minion", "name": "Sentry", "health": 30, "damage": 11, "armor": 0, "move": "stationary", "attack": "ranged", "range": 6, "color": Color("a773d5")},
    "wisp": {"role": "minion", "name": "Wisp", "health": 18, "damage": 7, "armor": 0, "move": "wander", "attack": "melee", "range": 1, "color": Color("68cee8")},
    "swarm": {"role": "minion", "name": "Swarm", "health": 16, "damage": 6, "armor": 0, "move": "fast_pursue", "attack": "melee", "range": 1, "color": Color("80d670")},
    "shield": {"role": "minion", "name": "Shieldbearer", "health": 58, "damage": 9, "armor": 8, "move": "pursue", "attack": "melee", "range": 1, "color": Color("7893bc")},
    "hunter": {"role": "midboss", "name": "Hunter", "health": 110, "damage": 16, "armor": 3, "move": "fast_pursue", "attack": "hybrid", "range": 4, "color": Color("d465a4")},
    "bulwark": {"role": "midboss", "name": "Bulwark", "health": 160, "damage": 22, "armor": 10, "move": "pursue", "attack": "melee", "range": 1, "color": Color("db8d3f")},
    "warden": {"role": "boss", "name": "Warden", "health": 320, "damage": 26, "armor": 6, "move": "boss", "attack": "hybrid", "range": 5, "color": Color("f06b4f")},
}

var id: int
var kind: String
var display_name: String
var role: String
var cell := Vector2i.ZERO
var max_health: int
var health: int
var damage: int
var armor: int
var move_style: String
var attack_style: String
var attack_range: int
var color: Color
var cooldown := 0


func _init(enemy_id: int, enemy_kind: String, spawn_cell: Vector2i) -> void:
    id = enemy_id
    kind = enemy_kind
    cell = spawn_cell

    var definition: Dictionary = DEFINITIONS.get(enemy_kind, DEFINITIONS["stalker"])
    display_name = String(definition["name"])
    role = String(definition["role"])
    max_health = int(definition["health"])
    health = max_health
    damage = int(definition["damage"])
    armor = int(definition["armor"])
    move_style = String(definition["move"])
    attack_style = String(definition["attack"])
    attack_range = int(definition["range"])
    color = definition["color"] as Color


func is_alive() -> bool:
    return health > 0


func take_damage(raw_damage: int) -> int:
    var actual_damage := maxi(1, raw_damage - armor)
    health = maxi(0, health - actual_damage)
    return actual_damage


func is_boss() -> bool:
    return role == "boss"


func health_ratio() -> float:
    return float(health) / float(max_health)


func status_text() -> String:
    return "%s %d/%d" % [display_name, health, max_health]
