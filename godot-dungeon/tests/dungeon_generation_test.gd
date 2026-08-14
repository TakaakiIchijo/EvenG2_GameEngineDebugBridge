extends SceneTree

const DungeonMapScript = preload("res://scripts/dungeon_map.gd")
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _initialize() -> void:
    var seeds := [17, 2026, 918273, 424242]
    for seed_value in seeds:
        var dungeon: Variant = DungeonMapScript.new(13, 13, seed_value)
        _assert_connected(dungeon)
        _assert_goal_reachable(dungeon)
        _assert_minimap_payload(dungeon)

    print("Dungeon generation test passed for %d seeds" % seeds.size())
    quit(0)


func _assert_connected(dungeon: Variant) -> void:
    var visited: Dictionary = {dungeon.start: true}
    var queue: Array[Vector2i] = [dungeon.start]
    var cursor := 0

    while cursor < queue.size():
        var current := queue[cursor]
        cursor += 1
        for direction_index in range(DIRECTIONS.size()):
            var direction: Vector2i = DIRECTIONS[direction_index]
            var next: Vector2i = current + direction
            if dungeon.is_walkable(next) and not visited.has(next):
                visited[next] = true
                queue.append(next)

    if visited.size() != dungeon.passage_count():
        push_error("Maze is not fully connected: %d/%d" % [visited.size(), dungeon.passage_count()])
        quit(1)


func _assert_goal_reachable(dungeon: Variant) -> void:
    if not dungeon.is_walkable(dungeon.goal):
        push_error("Goal cell is not walkable")
        quit(1)

    var current: Vector2i = dungeon.start
    dungeon.mark_explored(current)
    var safety_limit: int = int(dungeon.passage_count()) * 2
    var steps := 0
    while current != dungeon.goal and steps < safety_limit:
        var next: Vector2i = _next_step_toward_goal(dungeon, current)
        if next == current:
            push_error("No path from start to goal")
            quit(1)
        current = next
        dungeon.mark_explored(current)
        steps += 1

    if current != dungeon.goal:
        push_error("Goal was not reached within the safety limit")
        quit(1)


func _next_step_toward_goal(dungeon: Variant, origin: Vector2i) -> Vector2i:
    var came_from: Dictionary = {origin: origin}
    var queue: Array[Vector2i] = [origin]
    var cursor := 0

    while cursor < queue.size():
        var current := queue[cursor]
        cursor += 1
        if current == dungeon.goal:
            break
        for direction_index in range(DIRECTIONS.size()):
            var direction: Vector2i = DIRECTIONS[direction_index]
            var next: Vector2i = current + direction
            if dungeon.is_walkable(next) and not came_from.has(next):
                came_from[next] = current
                queue.append(next)

    if not came_from.has(dungeon.goal):
        return origin

    var step: Vector2i = dungeon.goal
    while came_from[step] != origin:
        step = came_from[step]
    return step


func _assert_minimap_payload(dungeon: Variant) -> void:
    var payload: Dictionary = dungeon.minimap_payload(dungeon.start, 0, 1, "exploring")
    var expected_size: int = int(dungeon.width) * int(dungeon.height)
    if payload["walls"].length() != expected_size or payload["explored"].length() != expected_size:
        push_error("Minimap payload does not match dungeon dimensions")
        quit(1)
