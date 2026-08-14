class_name DungeonMap
extends RefCounted

## 再現可能な奇数サイズの完全迷路。壁はtrue、通路はfalseで保持する。

const CARDINAL_DIRECTIONS := [
    Vector2i(0, -1),
    Vector2i(1, 0),
    Vector2i(0, 1),
    Vector2i(-1, 0),
]

var width: int
var height: int
var seed_value: int
var walls: Array[bool] = []
var explored: Array[bool] = []
var start := Vector2i(1, 1)
var goal := Vector2i(1, 1)


func _init(requested_width: int = 13, requested_height: int = 13, requested_seed: int = 0) -> void:
    width = _to_odd(maxi(requested_width, 5))
    height = _to_odd(maxi(requested_height, 5))
    seed_value = requested_seed if requested_seed != 0 else int(Time.get_unix_time_from_system())
    _generate()


func is_inside(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_walkable(cell: Vector2i) -> bool:
    return is_inside(cell) and not walls[_index(cell)]


func can_move(from: Vector2i, direction: Vector2i) -> bool:
    return is_walkable(from + direction)


func mark_explored(cell: Vector2i) -> bool:
    if not is_walkable(cell):
        return false
    var index := _index(cell)
    var was_new := not explored[index]
    explored[index] = true
    return was_new


func explored_count() -> int:
    var count := 0
    for value in explored:
        if value:
            count += 1
    return count


func passage_count() -> int:
    var count := 0
    for wall in walls:
        if not wall:
            count += 1
    return count


func minimap_payload(player: Vector2i, facing: int, revision: int, state_name: String) -> Dictionary:
    var wall_bits := ""
    var explored_bits := ""
    for index in range(walls.size()):
        wall_bits += "1" if walls[index] else "0"
        explored_bits += "1" if explored[index] else "0"

    return {
        "type": "minimap",
        "width": width,
        "height": height,
        "walls": wall_bits,
        "explored": explored_bits,
        "player": {"x": player.x, "y": player.y, "facing": facing},
        "goal": {"x": goal.x, "y": goal.y},
        "revision": revision,
        "state": state_name,
    }


func ascii_map(player: Vector2i) -> String:
    var rows: Array[String] = []
    for y in range(height):
        var row := ""
        for x in range(width):
            var cell := Vector2i(x, y)
            if cell == player:
                row += "@"
            elif cell == goal:
                row += "X"
            elif walls[_index(cell)]:
                row += "#"
            elif explored[_index(cell)]:
                row += "."
            else:
                row += " "
        rows.append(row)
    return "\n".join(rows)


func _generate() -> void:
    walls.clear()
    explored.clear()
    for _index_value in range(width * height):
        walls.append(true)
        explored.append(false)

    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    walls[_index(start)] = false

    var stack: Array[Vector2i] = [start]
    while not stack.is_empty():
        var current: Vector2i = stack.back()
        var candidates: Array[Vector2i] = []
        var shuffled_directions: Array[Vector2i] = _shuffled_directions(rng)
        for direction_index in range(shuffled_directions.size()):
            var direction: Vector2i = shuffled_directions[direction_index]
            var next: Vector2i = current + direction * 2
            if _is_interior(next) and walls[_index(next)]:
                candidates.append(direction)

        if candidates.is_empty():
            stack.pop_back()
            continue

        var direction: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
        var passage: Vector2i = current + direction
        var next_cell: Vector2i = current + direction * 2
        walls[_index(passage)] = false
        walls[_index(next_cell)] = false
        stack.append(next_cell)

    goal = _find_farthest_cell(start)
    mark_explored(start)


func _find_farthest_cell(origin: Vector2i) -> Vector2i:
    var distance: Array[int] = []
    distance.resize(width * height)
    distance.fill(-1)
    distance[_index(origin)] = 0

    var queue: Array[Vector2i] = [origin]
    var queue_index := 0
    var farthest: Vector2i = origin
    while queue_index < queue.size():
        var current: Vector2i = queue[queue_index]
        queue_index += 1
        if distance[_index(current)] > distance[_index(farthest)]:
            farthest = current

        for direction_index in range(CARDINAL_DIRECTIONS.size()):
            var direction: Vector2i = CARDINAL_DIRECTIONS[direction_index]
            var next: Vector2i = current + direction
            if not is_walkable(next):
                continue
            var next_index: int = _index(next)
            if distance[next_index] != -1:
                continue
            distance[next_index] = distance[_index(current)] + 1
            queue.append(next)

    return farthest


func _shuffled_directions(rng: RandomNumberGenerator) -> Array[Vector2i]:
    var directions: Array[Vector2i] = []
    directions.append_array(CARDINAL_DIRECTIONS)
    for index in range(directions.size() - 1, 0, -1):
        var swap_index := rng.randi_range(0, index)
        var temporary := directions[index]
        directions[index] = directions[swap_index]
        directions[swap_index] = temporary
    return directions


func _is_interior(cell: Vector2i) -> bool:
    return cell.x > 0 and cell.y > 0 and cell.x < width - 1 and cell.y < height - 1


func _index(cell: Vector2i) -> int:
    return cell.y * width + cell.x


func _to_odd(value: int) -> int:
    return value if value % 2 == 1 else value + 1
