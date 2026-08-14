extends SceneTree

const DungeonMapScript = preload("res://scripts/dungeon_map.gd")
const EnemyDirectorScript = preload("res://scripts/enemy_director.gd")


func _initialize() -> void:
    var dungeon: Variant = DungeonMapScript.new(13, 13, 20260814)
    var director: Variant = EnemyDirectorScript.new()
    director.create_encounter(dungeon)

    var enemies: Array = director.enemies
    _expect(enemies.size() == 10, "Expected ten enemy types")

    var kinds: Dictionary = {}
    var minions := 0
    var midbosses := 0
    var bosses := 0
    var move_styles: Dictionary = {}
    var attack_styles: Dictionary = {}
    for enemy in enemies:
        kinds[enemy.kind] = true
        move_styles[enemy.move_style] = true
        attack_styles[enemy.attack_style] = true
        if enemy.role == "minion":
            minions += 1
        elif enemy.role == "midboss":
            midbosses += 1
        elif enemy.role == "boss":
            bosses += 1
            _expect(enemy.cell == dungeon.goal, "Boss must guard the goal")

    _expect(kinds.size() == 10, "Enemy kinds must be unique")
    _expect(minions == 7 and midbosses == 2 and bosses == 1, "Expected 7 minions, 2 midbosses, and 1 boss")
    _expect(move_styles.size() >= 6, "Enemy roster needs varied movement styles")
    _expect(attack_styles.size() >= 3, "Enemy roster needs varied attack styles")

    var first_enemy: Variant = enemies[0]
    var health_before: int = first_enemy.health
    var dealt: int = first_enemy.take_damage(34)
    _expect(dealt >= 1 and first_enemy.health < health_before, "Damage should reduce enemy health")

    print("Enemy encounter test passed: 10 types, %d movement styles, %d attack styles" % [move_styles.size(), attack_styles.size()])
    quit(0)


func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    push_error(message)
    quit(1)
