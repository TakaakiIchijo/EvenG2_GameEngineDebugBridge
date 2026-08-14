extends SceneTree

const GameScene = preload("res://Main.tscn")
const DungeonItemScript = preload("res://scripts/dungeon_item.gd")


func _initialize() -> void:
    var game: Variant = GameScene.instantiate()
    root.add_child(game)
    await process_frame

    _expect(game._items.size() == 6, "Expected all six item types")
    for item in game._items:
        if item.kind == DungeonItemScript.Kind.AMMO_BOX:
            game.reserve_ammo = 0
        if item.kind == DungeonItemScript.Kind.MED_AMPOULE:
            game.health = 50

        game.player_cell = item.cell
        var message: String = game.call("_collect_item_at_player")
        _expect(not message.is_empty(), "Each item must report a pickup message")
        _expect(item.is_collected, "Item must become collected")
        var visual: Node3D = game._item_visuals.get(item.id)
        _expect(visual != null and not visual.visible, "Collected item visual must hide")

        if item.kind == DungeonItemScript.Kind.AMMO_BOX:
            _expect(game.reserve_ammo == 12, "Ammo box must replenish twelve reserve rounds")
        if item.kind == DungeonItemScript.Kind.MED_AMPOULE:
            _expect(game.health == 75, "Medical ampoule must restore twenty-five health")

    print("Item pickup test passed: six models, pickup messages, visual hiding, ammo, and health")
    quit(0)


func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    push_error(message)
    quit(1)
