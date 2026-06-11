extends Node

signal night_threat_detected(world_position: Vector2, stack_count: int)

const DETECTION_SUPPRESSION_PER_LIGHT := 0.4
const THREAT_ALERT_COOLDOWN_SECONDS := 2.5

var _active_lights: Dictionary = {}
var _active_power_consumers: Dictionary = {}
var _enemy_alert_expiry_by_id: Dictionary = {}


func register_light(light: Node2D, defense_radius: float, drain_units_per_minute: float) -> void:
	if not is_instance_valid(light):
		return
	var instance_id := light.get_instance_id()
	_active_lights[instance_id] = {
		&"node": light,
		&"radius": maxf(0.0, defense_radius),
		&"drain_units_per_minute": maxf(0.0, drain_units_per_minute),
	}


func unregister_light(light: Node2D) -> void:
	if light == null:
		return
	_active_lights.erase(light.get_instance_id())


func register_power_consumer(node: Node, drain_units_per_minute: float) -> void:
	if not is_instance_valid(node):
		return
	_active_power_consumers[node.get_instance_id()] = {
		&"node": node,
		&"drain_units_per_minute": maxf(0.0, drain_units_per_minute),
	}


func unregister_power_consumer(node: Node) -> void:
	if node == null:
		return
	_active_power_consumers.erase(node.get_instance_id())


func get_active_light_count() -> int:
	_prune_invalid_lights()
	return _active_lights.size()


func get_total_drain_per_second() -> float:
	_prune_invalid_lights()
	_prune_invalid_power_consumers()
	var total_drain_per_minute := 0.0
	for light_state: Dictionary in _active_lights.values():
		total_drain_per_minute += float(light_state.get(&"drain_units_per_minute", 0.0))
	for consumer_state: Dictionary in _active_power_consumers.values():
		total_drain_per_minute += float(consumer_state.get(&"drain_units_per_minute", 0.0))
	return total_drain_per_minute / 60.0


func get_light_stack_at(world_position: Vector2) -> int:
	_prune_invalid_lights()
	var stack_count := 0
	for light_state: Dictionary in _active_lights.values():
		var light_node: Node2D = light_state.get(&"node", null) as Node2D
		if light_node == null:
			continue
		var defense_radius := float(light_state.get(&"radius", 0.0))
		if defense_radius <= 0.0:
			continue
		if light_node.global_position.distance_to(world_position) <= defense_radius:
			stack_count += 1
	return stack_count


func get_detection_multiplier_at(world_position: Vector2) -> float:
	var stack_count := get_light_stack_at(world_position)
	return maxf(0.0, 1.0 - (DETECTION_SUPPRESSION_PER_LIGHT * float(stack_count)))


func is_position_in_powered_light(world_position: Vector2) -> bool:
	return get_light_stack_at(world_position) > 0


func report_night_threat(enemy_id: int, world_position: Vector2) -> void:
	if enemy_id <= 0:
		return
	var now_seconds := Time.get_ticks_msec() / 1000.0
	var expiry := float(_enemy_alert_expiry_by_id.get(enemy_id, 0.0))
	if now_seconds < expiry:
		return
	_enemy_alert_expiry_by_id[enemy_id] = now_seconds + THREAT_ALERT_COOLDOWN_SECONDS
	night_threat_detected.emit(world_position, get_light_stack_at(world_position))


func _prune_invalid_lights() -> void:
	var stale_ids: Array[int] = []
	for instance_id_variant in _active_lights.keys():
		var instance_id := int(instance_id_variant)
		var light_state: Dictionary = _active_lights[instance_id]
		var light_node: Node2D = light_state.get(&"node", null) as Node2D
		if not is_instance_valid(light_node):
			stale_ids.append(instance_id)
	for instance_id in stale_ids:
		_active_lights.erase(instance_id)


func _prune_invalid_power_consumers() -> void:
	var stale_ids: Array[int] = []
	for instance_id_variant in _active_power_consumers.keys():
		var instance_id := int(instance_id_variant)
		var consumer_state: Dictionary = _active_power_consumers[instance_id]
		var consumer_node: Node = consumer_state.get(&"node", null) as Node
		if not is_instance_valid(consumer_node):
			stale_ids.append(instance_id)
	for instance_id in stale_ids:
		_active_power_consumers.erase(instance_id)
