extends Node

signal switchboard_changed

const CONSUMER_PERIMETER_LIGHTS := &"perimeter_lights"
const CONSUMER_TRAP_NETWORK := &"trap_network"
const CONSUMER_FURNACE_BOOST := &"furnace_boost"
const CONSUMER_CHEM_BENCH_BOOST := &"chem_bench_boost"

const DISTRIBUTION_CAPACITY_UNITS_PER_MINUTE := 4.0
const FURNACE_BOOST_DRAIN_UNITS_PER_MINUTE := 1.5
const CHEM_BENCH_BOOST_DRAIN_UNITS_PER_MINUTE := 1.0

const CONSUMER_INFO := {
	CONSUMER_PERIMETER_LIGHTS: {&"label": "Perimeter Lights"},
	CONSUMER_TRAP_NETWORK: {&"label": "Trap Network"},
	CONSUMER_FURNACE_BOOST: {&"label": "Furnace Boost"},
	CONSUMER_CHEM_BENCH_BOOST: {&"label": "Chem Bench Boost"},
}

var _consumer_enabled: Dictionary = {}


func _ready() -> void:
	for consumer_id: StringName in CONSUMER_INFO.keys():
		_consumer_enabled[consumer_id] = true
	EventBus.register_service(EventBus.SERVICE_POWER_SWITCHBOARD, self)


func _exit_tree() -> void:
	EventBus.unregister_service(EventBus.SERVICE_POWER_SWITCHBOARD, self)


func is_consumer_enabled(consumer_id: StringName) -> bool:
	if not _consumer_enabled.has(consumer_id):
		return true
	return bool(_consumer_enabled[consumer_id])


func set_consumer_enabled(consumer_id: StringName, enabled: bool) -> void:
	if not CONSUMER_INFO.has(consumer_id):
		return
	if bool(_consumer_enabled.get(consumer_id, true)) == enabled:
		return
	_consumer_enabled[consumer_id] = enabled
	if GameManager != null and GameManager.has_method("mark_dirty"):
		GameManager.mark_dirty()
	switchboard_changed.emit()


func get_total_capacity_units_per_minute() -> float:
	return DISTRIBUTION_CAPACITY_UNITS_PER_MINUTE


func get_total_draw_units_per_minute() -> float:
	var total_draw := 0.0
	for consumer_id: StringName in CONSUMER_INFO.keys():
		total_draw += get_consumer_draw_units_per_minute(consumer_id)
	return total_draw


func is_over_capacity() -> bool:
	return get_total_draw_units_per_minute() > get_total_capacity_units_per_minute()


func get_consumer_draw_units_per_minute(consumer_id: StringName) -> float:
	if not is_consumer_enabled(consumer_id):
		return 0.0

	match consumer_id:
		CONSUMER_PERIMETER_LIGHTS:
			return _sum_group_drain(&"powered_light")
		CONSUMER_TRAP_NETWORK:
			return _sum_group_drain(&"electric_trap")
		CONSUMER_FURNACE_BOOST:
			return _count_active_station_boosts(&"furnace_station") * FURNACE_BOOST_DRAIN_UNITS_PER_MINUTE
		CONSUMER_CHEM_BENCH_BOOST:
			return _count_active_station_boosts(&"chem_bench_station") * CHEM_BENCH_BOOST_DRAIN_UNITS_PER_MINUTE

	return 0.0


func allows_furnace_boost() -> bool:
	return is_consumer_enabled(CONSUMER_FURNACE_BOOST)


func allows_chem_bench_boost() -> bool:
	return is_consumer_enabled(CONSUMER_CHEM_BENCH_BOOST)


func _sum_group_drain(group_name: StringName) -> float:
	var total_draw := 0.0
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		if node.has_method("get_power_drain_units_per_minute"):
			total_draw += float(node.call("get_power_drain_units_per_minute"))
	return total_draw


func _count_active_station_boosts(group_name: StringName) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		count += 1
	return count
