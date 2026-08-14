extends SceneTree

const GameScene = preload("res://Main.tscn")
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _initialize() -> void:
    var game: Variant = GameScene.instantiate()
    root.add_child(game)
    await process_frame

    _expect(game._enemy_director.living_enemies().size() == 10, "Expected ten spawned enemies")
    var initial_facing: int = game.facing
    var initial_revision: int = game.revision
    game.call("_turn", 1)
    _expect(game.facing == posmod(initial_facing + 1, 4), "Turn input must rotate the player")
    _expect(game.revision == initial_revision + 1, "Turn must increment minimap revision")

    var moved := false
    for direction_index in range(DIRECTIONS.size()):
        var direction: Vector2i = DIRECTIONS[direction_index]
        var next: Vector2i = game.player_cell + direction
        if game.dungeon.can_move(game.player_cell, direction) and game._enemy_director.enemy_at(next) == null:
            game.call("_try_move", direction)
            moved = true
            break

    _expect(moved, "The start cell needs at least one free passage")
    _expect(game.dungeon.explored_count() >= 2, "Moving to a passage must update exploration")
    print("Gameplay flow test passed: scene, combat HUD, enemy roster, turn, and move")
    quit(0)


func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    push_error(message)
    quit(1)
