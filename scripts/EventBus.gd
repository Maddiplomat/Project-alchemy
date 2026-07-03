extends Node

# Global broadcast events plus runtime service discovery live here.
# Use owner-local signals for subsystem-internal state, and EventBus for
# cross-system events that multiple unrelated systems react to.
signal discovery_made(output_id: StringName)
signal discovery_entry_added(entry: Dictionary)
signal crafting_completed(recipe_id: StringName, output: Dictionary)
signal buildable_placed(buildable_id: StringName)
signal night_threat_detected(world_position: Vector2, stack_count: int)
signal loop_milestone_reached(tier: int)
signal chemistry_lesson_triggered(lesson_id: StringName, message: String)
signal service_registered(service_id: StringName, service: Node)
signal service_unregistered(service_id: StringName)

const SERVICE_CAMERA_SHAKE := &"camera_shake"
const SERVICE_MAP_MARKERS := &"map_markers"
const SERVICE_WORLD_SAVE_DATA := &"world_save_data"
const SERVICE_BASE_GRID := &"base_grid"
const SERVICE_POWER_SWITCHBOARD := &"power_switchboard"
const SERVICE_COLD_SYSTEM := &"cold_system"
const SERVICE_NIGHT_VISUAL_CONTROLLER := &"night_visual_controller"

var _services: Dictionary[StringName, Node] = {}


func register_service(service_id: StringName, service: Node) -> void:
	if service_id.is_empty() or service == null:
		return
	_services[service_id] = service
	service_registered.emit(service_id, service)


func unregister_service(service_id: StringName, service: Node) -> void:
	if service_id.is_empty():
		return
	if _services.get(service_id) != service:
		return
	_services.erase(service_id)
	service_unregistered.emit(service_id)


func get_service(service_id: StringName) -> Node:
	var service := _services.get(service_id) as Node
	if service != null and is_instance_valid(service):
		return service
	_services.erase(service_id)
	return null


func get_camera_shake() -> Node:
	return get_service(SERVICE_CAMERA_SHAKE)


func get_map_markers() -> Node:
	return get_service(SERVICE_MAP_MARKERS)


func get_world_save_data() -> Node:
	return get_service(SERVICE_WORLD_SAVE_DATA)


func get_base_grid() -> Node:
	return get_service(SERVICE_BASE_GRID)


func get_power_switchboard() -> Node:
	return get_service(SERVICE_POWER_SWITCHBOARD)


func get_cold_system() -> Node:
	return get_service(SERVICE_COLD_SYSTEM)


func get_night_visual_controller() -> Node:
	return get_service(SERVICE_NIGHT_VISUAL_CONTROLLER)


func emit_discovery_made(output_id: StringName) -> void:
	if output_id.is_empty():
		return
	discovery_made.emit(output_id)


func emit_discovery_entry_added(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	discovery_entry_added.emit(entry.duplicate(true))


func emit_crafting_completed(recipe_id: StringName, output: Dictionary) -> void:
	if recipe_id.is_empty():
		return
	crafting_completed.emit(recipe_id, output.duplicate(true))


func emit_buildable_placed(buildable_id: StringName) -> void:
	if buildable_id.is_empty():
		return
	buildable_placed.emit(buildable_id)


func emit_night_threat_detected(world_position: Vector2, stack_count: int) -> void:
	night_threat_detected.emit(world_position, stack_count)


func emit_loop_milestone_reached(tier: int) -> void:
	if tier <= 0:
		return
	loop_milestone_reached.emit(tier)


func emit_chemistry_lesson_triggered(lesson_id: StringName, message: String) -> void:
	if lesson_id.is_empty() or message.strip_edges().is_empty():
		return
	chemistry_lesson_triggered.emit(lesson_id, message)
