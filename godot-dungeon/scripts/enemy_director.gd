class_name EnemyDirector
extends RefCounted

const EnemyScript = preload("res://scripts/dungeon_enemy.gd")
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const ENCOUNTER_ORDER := [
    "stalker", "skirmisher", "charger", "sentry", "wisp", "swarm", "shield", "hunter", "bulwark", "warden",
]

var enemies: Array[Variant] = []
var _rng := RandomNumberGenerator.new()


func create_encounter(dungeon: Variant) -> void:
    enemies.clear()
    _rng.seed = int(dungeon.seed_value) ^ 0x5D3E27

    var available: Array[Vector2i] = _spawn_cells(dungeon)
    for spawn_index in range(ENCOUNTER_ORDER.size()):
        if available.is_empty():
            break
        var cell_index := _rng.randi_range(0, available.size() - 1)
        var spawn_cell: Vector2i = available[cell_index]
        available.remove_at(cell_index)
        var enemy: Variant = EnemyScript.new(spawn_index + 1, String(ENCOUNTER_ORDER[spawn_index]), spawn_cell)
        enemies.append(enemy)

    # ボスは出口を守る。出口セルが通路なら最終的に必ず配置する。
    for enemy in enemies:
        if enemy.is_boss():
            enemy.cell = dungeon.goal


func living_enemies() -> Array[Variant]:
    var result: Array[Variant] = []
    for enemy in enemies:
        if enemy.is_alive():
            result.append(enemy)
    return result


func enemy_at(cell: Vector2i) -> Variant:
    for enemy in enemies:
        if enemy.is_alive() and enemy.cell == cell:
            return enemy
    return null


func take_shot(dungeon: Variant, origin: Vector2i, direction: Vector2i, damage: int) -> Dictionary:
    for distance in range(1, 8):
        var target: Vector2i = origin + direction * distance
        if not dungeon.is_walkable(target):
            return {"result": "wall", "message": "弾丸は壁に当たりました"}
        var enemy: Variant = enemy_at(target)
        if enemy != null:
            var actual_damage: int = enemy.take_damage(damage)
            var message := "%sへ%dダメージ" % [enemy.display_name, actual_damage]
            if not enemy.is_alive():
                message += " — 撃破"
            return {"result": "hit", "enemy": enemy, "message": message}
    return {"result": "miss", "message": "命中する敵はいません"}


func advance_turn(dungeon: Variant, player_cell: Vector2i) -> Array[Dictionary]:
    var events: Array[Dictionary] = []
    var occupied: Dictionary = {}
    for enemy in living_enemies():
        occupied[enemy.cell] = true

    for enemy in living_enemies():
        occupied.erase(enemy.cell)
        var event := _act_enemy(dungeon, enemy, player_cell, occupied)
        occupied[enemy.cell] = true
        if not event.is_empty():
            events.append(event)

    return events


func _act_enemy(dungeon: Variant, enemy: Variant, player_cell: Vector2i, occupied: Dictionary) -> Dictionary:
    if enemy.cooldown > 0:
        enemy.cooldown -= 1
        return {}

    var distance := _manhattan(enemy.cell, player_cell)
    if distance <= int(enemy.attack_range):
        enemy.cooldown = 1 if enemy.role == "minion" else 0
        return {"type": "attack", "enemy": enemy, "damage": enemy.damage, "message": "%sの攻撃" % enemy.display_name}

    var move_count := 1
    if enemy.move_style == "fast_pursue" or enemy.move_style == "charge":
        move_count = 2
    elif enemy.move_style == "boss" and enemy.health_ratio() <= 0.5:
        move_count = 2

    if enemy.move_style == "stationary":
        return {}

    for _move_index in range(move_count):
        var next := _choose_step(dungeon, enemy, player_cell, occupied)
        if next == enemy.cell:
            break
        enemy.cell = next

    return {"type": "move", "enemy": enemy, "message": "%sが接近" % enemy.display_name}


func _choose_step(dungeon: Variant, enemy: Variant, player_cell: Vector2i, occupied: Dictionary) -> Vector2i:
    if enemy.move_style == "wander":
        return _random_step(dungeon, enemy.cell, occupied)

    if enemy.move_style == "keep_range" and _manhattan(enemy.cell, player_cell) <= 2:
        return _flee_step(dungeon, enemy.cell, player_cell, occupied)

    return _path_step(dungeon, enemy.cell, player_cell, occupied)


func _path_step(dungeon: Variant, origin: Vector2i, target: Vector2i, occupied: Dictionary) -> Vector2i:
    var came_from: Dictionary = {origin: origin}
    var queue: Array[Vector2i] = [origin]
    var cursor := 0

    while cursor < queue.size():
        var current: Vector2i = queue[cursor]
        cursor += 1
        if current == target:
            break
        for direction_index in range(DIRECTIONS.size()):
            var direction: Vector2i = DIRECTIONS[direction_index]
            var next: Vector2i = current + direction
            if not dungeon.is_walkable(next) or occupied.has(next) or came_from.has(next):
                continue
            came_from[next] = current
            queue.append(next)

    if not came_from.has(target):
        return origin
    var step: Vector2i = target
    while came_from[step] != origin:
        step = came_from[step]
    return step


func _flee_step(dungeon: Variant, origin: Vector2i, player_cell: Vector2i, occupied: Dictionary) -> Vector2i:
    var best := origin
    var best_distance := _manhattan(origin, player_cell)
    for direction_index in range(DIRECTIONS.size()):
        var direction: Vector2i = DIRECTIONS[direction_index]
        var next: Vector2i = origin + direction
        if dungeon.is_walkable(next) and not occupied.has(next):
            var next_distance := _manhattan(next, player_cell)
            if next_distance > best_distance:
                best = next
                best_distance = next_distance
    return best


func _random_step(dungeon: Variant, origin: Vector2i, occupied: Dictionary) -> Vector2i:
    var candidates: Array[Vector2i] = []
    for direction_index in range(DIRECTIONS.size()):
        var direction: Vector2i = DIRECTIONS[direction_index]
        var next: Vector2i = origin + direction
        if dungeon.is_walkable(next) and not occupied.has(next):
            candidates.append(next)
    if candidates.is_empty():
        return origin
    return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _spawn_cells(dungeon: Variant) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for y in range(dungeon.height):
        for x in range(dungeon.width):
            var cell := Vector2i(x, y)
            var distance_from_start := _manhattan(cell, dungeon.start)
            if dungeon.is_walkable(cell) and cell != dungeon.start and cell != dungeon.goal and distance_from_start >= 6:
                result.append(cell)
    return result


func _manhattan(a: Vector2i, b: Vector2i) -> int:
    return absi(a.x - b.x) + absi(a.y - b.y)
