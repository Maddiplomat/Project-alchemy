extends Node2D

const IronGolemScene = preload("res://scenes/IronGolem.tscn")

var _failures := 0


func _ready() -> void:
	_run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var golem = IronGolemScene.instantiate()
	add_child(golem)

	var nav_agent := golem.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	var scan_data: Dictionary = golem.get_scan_data()
	var resistances: Dictionary = golem.resistances

	_assert(golem is CharacterBody2D, "Expected IronGolem root to be CharacterBody2D.")
	_assert(nav_agent != null, "Expected NavigationAgent2D child on IronGolem.")
	_assert(golem.is_in_group(&"enemy"), "Expected IronGolem to join enemy group.")
	_assert(golem.health == 120, "Expected IronGolem health to default to 120.")
	_assert(is_equal_approx(golem.patrol_radius, 96.0), "Expected patrol radius to default to 96.")
	_assert(is_equal_approx(golem.detection_radius, 180.0), "Expected detection radius to default to 180.")
	_assert(is_equal_approx(golem.attack_range, 48.0), "Expected attack range to default to 48.")
	_assert(is_equal_approx(golem.move_speed, 60.0), "Expected move speed to default to 60.")
	_assert(is_equal_approx(float(resistances.get(&"oxidation", 0.0)), 3.0), "Expected oxidation multiplier 3.0.")
	_assert(is_equal_approx(float(resistances.get(&"physical_blunt", -1.0)), 0.0), "Expected blunt immunity multiplier 0.0.")
	_assert(scan_data.get(&"weaknesses", []).has(&"oxidation"), "Expected oxidation in weaknesses.")
	_assert(scan_data.get(&"immunities", []).has(&"physical_blunt"), "Expected physical_blunt immunity.")

	if _failures == 0:
		print("IronGolemLoadTest passed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return

	_failures += 1
	push_error(message)
