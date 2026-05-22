extends Node2D

const IronGolemScene = preload("res://scenes/IronGolem.tscn")

var _failures := 0
var _waypoint_events: Array[int] = []


func _ready() -> void:
	await _run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var golem = IronGolemScene.instantiate()
	golem.patrol_waypoint_a = Vector2(-36.0, 0.0)
	golem.patrol_waypoint_b = Vector2(36.0, 0.0)
	add_child(golem)
	golem.patrol_waypoint_reached.connect(_on_patrol_waypoint_reached)
	await get_tree().process_frame
	print("IronGolemPatrolSimulation patrol_points=%s target=%s state=%s" % [golem._patrol_points, golem.target_position, golem.current_state])

	var timeout_seconds := 12.0
	var elapsed := 0.0
	while elapsed < timeout_seconds and _waypoint_events.size() < 4:
		golem.simulate_step(1.0 / 60.0)
		elapsed += 1.0 / 60.0

	print("IronGolemPatrolSimulation waypoint_events=%s position=%s target=%s patrol_index=%s" % [_waypoint_events, golem.global_position, golem.target_position, golem._current_patrol_index])

	_assert(_waypoint_events.size() >= 4, "Expected at least four patrol waypoint events.")
	if _waypoint_events.size() >= 4:
		_assert(_waypoint_events[0] == 0, "Expected first patrol waypoint event to be waypoint 0.")
		_assert(_waypoint_events[1] == 1, "Expected second patrol waypoint event to be waypoint 1.")
		_assert(_waypoint_events[2] == 0, "Expected third patrol waypoint event to loop back to waypoint 0.")
		_assert(_waypoint_events[3] == 1, "Expected fourth patrol waypoint event to continue cycling to waypoint 1.")

	var waypoint_distance := minf(
		golem.global_position.distance_to(golem.spawn_position + golem.patrol_waypoint_a),
		golem.global_position.distance_to(golem.spawn_position + golem.patrol_waypoint_b)
	)
	_assert(waypoint_distance <= golem.patrol_radius + 4.0, "Expected golem to remain inside patrol bounds.")

	if _failures == 0:
		print("IronGolemPatrolSimulation passed.")


func _on_patrol_waypoint_reached(waypoint_index: int) -> void:
	_waypoint_events.append(waypoint_index)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return

	_failures += 1
	push_error(message)
