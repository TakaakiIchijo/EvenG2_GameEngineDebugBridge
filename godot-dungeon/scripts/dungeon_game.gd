class_name DungeonGame
extends Node3D

signal minimap_changed(payload: Dictionary)
signal game_state_changed(state_name: String)
signal shot_fired(origin: Vector2i, direction: Vector2i, damage: int)
signal player_damaged(current_health: int, source_name: String)

const TILE_SIZE := 2.4
const WALL_HEIGHT := 2.4
const MOVE_DURATION := 0.16
const WEAPON_DAMAGE := 34
const MAX_HEALTH := 100
const MAGAZINE_SIZE := 12
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const EnemyDirectorScript = preload("res://scripts/enemy_director.gd")
const DungeonBridgeClientScript = preload("res://scripts/dungeon_bridge_client.gd")

enum GameState { EXPLORING, CLEARED }

@export var dungeon_width := 13
@export var dungeon_height := 13
@export var initial_seed := 0

@onready var _maze_root: Node3D = %MazeRoot
@onready var _enemy_root: Node3D = %EnemyRoot
@onready var _player_rig: Node3D = %PlayerRig
@onready var _status_label: Label = %StatusLabel
@onready var _seed_label: Label = %SeedLabel
@onready var _minimap_label: Label = %MinimapLabel
@onready var _hint_label: Label = %HintLabel
@onready var _combat_label: Label = %CombatLabel
@onready var _weapon_light: OmniLight3D = %WeaponLight

var dungeon: DungeonMap
var player_cell := Vector2i(1, 1)
var facing := 0
var revision := 0
var game_state := GameState.EXPLORING
var health := MAX_HEALTH
var ammo := MAGAZINE_SIZE
var reserve_ammo := 48
var _is_moving := false
var _weapon_flash_timer := 0.0
var _wall_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _goal_material: StandardMaterial3D
var _enemy_director: Variant
var _enemy_visuals: Dictionary = {}
var _bridge_client: Variant


func _ready() -> void:
    _wall_material = _make_material(Color("284568"), 0.72, 0.0)
    _floor_material = _make_material(Color("122033"), 0.9, 0.05)
    _goal_material = _make_material(Color("f4ba49"), 0.35, 0.45)
    _enemy_director = EnemyDirectorScript.new()
    _bridge_client = DungeonBridgeClientScript.new()
    _bridge_client.connection_changed.connect(_on_bridge_connection_changed)
    minimap_changed.connect(_on_minimap_changed)
    var bridge_error: Error = _bridge_client.connect_to_server(_read_bridge_url_from_arguments())
    if bridge_error != OK:
        push_warning("[DungeonBridge] Bridge connection request failed: %s" % error_string(bridge_error))
    new_dungeon(initial_seed)


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return

    if event.keycode == KEY_R:
        new_dungeon(0)
        return
    if game_state != GameState.EXPLORING or _is_moving:
        return

    match event.keycode:
        KEY_A, KEY_LEFT:
            _turn(-1)
        KEY_D, KEY_RIGHT:
            _turn(1)
        KEY_W, KEY_UP:
            var forward: Vector2i = DIRECTIONS[facing]
            _try_move(forward)
        KEY_S, KEY_DOWN:
            var backward: Vector2i = -DIRECTIONS[facing]
            _try_move(backward)
        KEY_SPACE:
            _shoot()
        KEY_F:
            _reload()


func new_dungeon(seed_override: int = 0) -> void:
    var actual_seed := seed_override
    if actual_seed == 0:
        actual_seed = int(Time.get_unix_time_from_system())

    dungeon = DungeonMap.new(dungeon_width, dungeon_height, actual_seed)
    player_cell = dungeon.start
    facing = 0
    revision = 0
    game_state = GameState.EXPLORING
    health = MAX_HEALTH
    ammo = MAGAZINE_SIZE
    reserve_ammo = 48
    _rebuild_maze_geometry()
    _enemy_director.create_encounter(dungeon)
    _rebuild_enemy_visuals()
    _snap_player_to_cell()
    _update_ui("新しいダンジョンを生成しました")
    _emit_minimap()


func current_minimap_payload() -> Dictionary:
    return dungeon.minimap_payload(player_cell, facing, revision, _state_name())


func _shoot() -> void:
    if ammo <= 0:
        _update_ui("弾倉が空です。Fキーでリロードします")
        return

    ammo -= 1
    _weapon_flash_timer = 0.08
    _weapon_light.light_energy = 10.0
    var direction: Vector2i = DIRECTIONS[facing]
    shot_fired.emit(player_cell, direction, WEAPON_DAMAGE)
    var result: Dictionary = _enemy_director.take_shot(dungeon, player_cell, direction, WEAPON_DAMAGE)
    _update_ui(String(result["message"]))
    _refresh_enemy_visuals()
    _advance_enemy_turn()


func _reload() -> void:
    if ammo >= MAGAZINE_SIZE or reserve_ammo <= 0:
        _update_ui("リロードできません")
        return

    var required := MAGAZINE_SIZE - ammo
    var loaded := mini(required, reserve_ammo)
    ammo += loaded
    reserve_ammo -= loaded
    _update_ui("リロードしました")


func receive_damage(amount: int, source_name: String) -> void:
    if game_state != GameState.EXPLORING:
        return

    health = maxi(0, health - amount)
    player_damaged.emit(health, source_name)
    if health == 0:
        game_state = GameState.CLEARED
        _update_ui("撃破されました。Rキーで新しいダンジョンを生成できます")
        game_state_changed.emit("defeated")
        _emit_minimap()
    else:
        _update_ui("%sから%dダメージを受けました" % [source_name, amount])


func _process(delta: float) -> void:
    if _bridge_client != null:
        _bridge_client.poll()
    if _weapon_flash_timer > 0.0:
        _weapon_flash_timer = maxf(0.0, _weapon_flash_timer - delta)
        if _weapon_flash_timer == 0.0:
            _weapon_light.light_energy = 0.0


func _exit_tree() -> void:
    if _bridge_client != null:
        _bridge_client.close()


func _on_minimap_changed(payload: Dictionary) -> void:
    if _bridge_client != null:
        _bridge_client.queue_minimap(payload)


func _on_bridge_connection_changed(_connected: bool, detail: String) -> void:
    print("[Even] Dungeon bridge: %s" % detail)


func _read_bridge_url_from_arguments() -> String:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--bridge-url="):
            return argument.trim_prefix("--bridge-url=")
    return "ws://127.0.0.1:8766"


func _try_move(direction: Vector2i) -> void:
    var next: Vector2i = player_cell + direction
    if not dungeon.can_move(player_cell, direction):
        _update_ui("壁に阻まれています")
        return

    var blocking_enemy: Variant = _enemy_director.enemy_at(next)
    if blocking_enemy != null:
        _update_ui("%sが行く手を塞いでいます" % blocking_enemy.display_name)
        return

    player_cell = next
    var discovered_new_cell := dungeon.mark_explored(player_cell)
    revision += 1
    _animate_player_to_cell()

    if player_cell == dungeon.goal:
        game_state = GameState.CLEARED
        _update_ui("脱出成功。Rキーで新しい迷路を生成できます")
        game_state_changed.emit(_state_name())
    elif discovered_new_cell:
        _update_ui("新しい区画を探索しました")
    else:
        _update_ui("探索済みの区画です")

    _emit_minimap()
    _advance_enemy_turn()


func _turn(amount: int) -> void:
    facing = posmod(facing + amount, DIRECTIONS.size())
    revision += 1
    _animate_player_rotation()
    _update_ui("向きを変更しました")
    _emit_minimap()
    _advance_enemy_turn()


func _rebuild_maze_geometry() -> void:
    for child in _maze_root.get_children():
        child.queue_free()

    var floor := MeshInstance3D.new()
    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(dungeon.width * TILE_SIZE, dungeon.height * TILE_SIZE)
    floor.mesh = floor_mesh
    floor.material_override = _floor_material
    floor.position = Vector3((dungeon.width - 1) * TILE_SIZE * 0.5, 0.0, (dungeon.height - 1) * TILE_SIZE * 0.5)
    _maze_root.add_child(floor)

    for y in range(dungeon.height):
        for x in range(dungeon.width):
            var cell := Vector2i(x, y)
            if dungeon.walls[y * dungeon.width + x]:
                _add_wall(cell)

    var goal_marker := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.28
    cylinder.bottom_radius = 0.45
    cylinder.height = 1.3
    goal_marker.mesh = cylinder
    goal_marker.material_override = _goal_material
    goal_marker.position = _cell_to_world(dungeon.goal) + Vector3(0.0, 0.65, 0.0)
    _maze_root.add_child(goal_marker)

    var goal_light := OmniLight3D.new()
    goal_light.light_color = Color("ffd166")
    goal_light.light_energy = 2.5
    goal_light.omni_range = 5.0
    goal_light.position = goal_marker.position + Vector3(0.0, 1.0, 0.0)
    _maze_root.add_child(goal_light)


func _add_wall(cell: Vector2i) -> void:
    var wall := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(TILE_SIZE, WALL_HEIGHT, TILE_SIZE)
    wall.mesh = mesh
    wall.material_override = _wall_material
    wall.position = _cell_to_world(cell) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
    _maze_root.add_child(wall)


func _rebuild_enemy_visuals() -> void:
    for child in _enemy_root.get_children():
        child.queue_free()
    _enemy_visuals.clear()

    for enemy in _enemy_director.living_enemies():
        var visual := MeshInstance3D.new()
        if enemy.role == "boss":
            var boss_mesh := CylinderMesh.new()
            boss_mesh.top_radius = 0.72
            boss_mesh.bottom_radius = 0.92
            boss_mesh.height = 2.2
            visual.mesh = boss_mesh
        elif enemy.role == "midboss":
            var midboss_mesh := BoxMesh.new()
            midboss_mesh.size = Vector3(1.25, 1.65, 1.25)
            visual.mesh = midboss_mesh
        else:
            var minion_mesh := SphereMesh.new()
            minion_mesh.radius = 0.52
            minion_mesh.height = 1.04
            visual.mesh = minion_mesh

        visual.material_override = _make_material(enemy.color, 0.45, 0.15)
        visual.position = _cell_to_world(enemy.cell) + Vector3(0.0, _enemy_visual_height(enemy), 0.0)
        _enemy_root.add_child(visual)
        _enemy_visuals[enemy.id] = visual


func _refresh_enemy_visuals() -> void:
    for enemy in _enemy_director.enemies:
        var visual: MeshInstance3D = _enemy_visuals.get(enemy.id)
        if visual == null:
            continue
        visual.visible = enemy.is_alive()
        if enemy.is_alive():
            visual.position = _cell_to_world(enemy.cell) + Vector3(0.0, _enemy_visual_height(enemy), 0.0)


func _advance_enemy_turn() -> void:
    if game_state != GameState.EXPLORING:
        return

    var events: Array[Dictionary] = _enemy_director.advance_turn(dungeon, player_cell)
    for event in events:
        if String(event.get("type", "")) == "attack":
            var attacker: Variant = event["enemy"]
            receive_damage(int(event["damage"]), attacker.display_name)
            if game_state != GameState.EXPLORING:
                break

    _refresh_enemy_visuals()
    _update_ui(_status_label.text)


func _enemy_visual_height(enemy: Variant) -> float:
    if enemy.role == "boss":
        return 1.1
    if enemy.role == "midboss":
        return 0.83
    return 0.52


func _snap_player_to_cell() -> void:
    _player_rig.position = _cell_to_world(player_cell) + Vector3(0.0, 1.58, 0.0)
    _player_rig.rotation.y = facing * PI * 0.5


func _animate_player_to_cell() -> void:
    _is_moving = true
    var tween := create_tween()
    tween.tween_property(_player_rig, "position", _cell_to_world(player_cell) + Vector3(0.0, 1.58, 0.0), MOVE_DURATION)
    tween.finished.connect(func() -> void: _is_moving = false)


func _animate_player_rotation() -> void:
    var tween := create_tween()
    tween.tween_property(_player_rig, "rotation:y", facing * PI * 0.5, MOVE_DURATION)


func _update_ui(message: String) -> void:
    _status_label.text = message
    _seed_label.text = "SEED  %d    EXPLORED  %d / %d" % [dungeon.seed_value, dungeon.explored_count(), dungeon.passage_count()]
    _combat_label.text = "HP  %03d      AMMO  %02d / %02d      HOSTILES  %02d" % [health, ammo, reserve_ammo, _enemy_director.living_enemies().size()]
    _minimap_label.text = dungeon.ascii_map(player_cell)
    _hint_label.text = "W/S: move  A/D: turn  SPACE: fire  F: reload  R: new dungeon\nEven G2: exploration minimap"


func _emit_minimap() -> void:
    minimap_changed.emit(current_minimap_payload())


func _state_name() -> String:
    return "cleared" if game_state == GameState.CLEARED else "exploring"


func _cell_to_world(cell: Vector2i) -> Vector3:
    return Vector3(cell.x * TILE_SIZE, 0.0, cell.y * TILE_SIZE)


func _make_material(color: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness_value
    material.metallic = metallic_value
    return material
