extends Node

signal carrier_risk_warning(element_id: StringName, seconds_remaining: int)
signal carrier_risk_cleared(element_id: StringName)
signal carrier_risk_ignition(element_id: StringName)

const CHECK_INTERVAL_SECONDS := 0.5
const WARNING_DURATION_SECONDS := 3.0
const LITHIUM_DEGRADE_INTERVAL_SECONDS := 1.0
const LITHIUM_ITEM_ID := &"lithium"
const LITHIUM_CHARGE_LOSS_PER_SECOND := 0.15
const LITHIUM_EXPLOSION_RADIUS_PIXELS := 16.0
const LITHIUM_EXPLOSION_DAMAGE := 15
const CHEMICAL_EXPLOSION_SCENE := preload("res://scenes/ChemicalExplosion.tscn")

var _check_timer: Timer = null
var _countdowns: Dictionary = {}
var _lithium_exposure_elapsed := 0.0
var _shelter_sources: Dictionary = {}
var _external_triggers: Dictionary = {}
var _external_trigger_reasons: Dictionary = {}


func _ready() -> void:
	_check_timer = Timer.new()
	_check_timer.wait_time = CHECK_INTERVAL_SECONDS
	_check_timer.one_shot = false
	_check_timer.timeout.connect(_on_check_timeout)
	add_child(_check_timer)
	_check_timer.start()


func _on_check_timeout() -> void:
	_process_lithium_exposure()

	var active_volatile_items := _get_active_volatile_items()
	var active_item_lookup: Dictionary = {}
	if _countdowns.has(LITHIUM_ITEM_ID):
		active_item_lookup[LITHIUM_ITEM_ID] = true
	for element_id: StringName in active_volatile_items:
		active_item_lookup[element_id] = true

	for element_id: StringName in active_volatile_items:
		var should_trigger := _should_trigger_risk_for(element_id)
		if should_trigger:
			_advance_countdown(element_id)
		else:
			_reset_countdown(element_id)

	for tracked_id: StringName in _countdowns.keys():
		if not active_item_lookup.has(tracked_id):
			_reset_countdown(tracked_id)


func _get_active_volatile_items() -> Array[StringName]:
	var volatile_items: Array[StringName] = []
	for item_id: StringName in InventoryManager.items.keys():
		if item_id == LITHIUM_ITEM_ID:
			continue
		var element_data: Dictionary = ElementDatabase.get_element(item_id)
		if element_data.is_empty():
			continue
		if String(element_data.get(&"category", "")).to_lower() != "volatile":
			continue
		volatile_items.append(item_id)
	return volatile_items


func _should_trigger_risk_for(element_id: StringName) -> bool:
	if bool(_external_triggers.get(element_id, false)):
		return true

	var element_data: Dictionary = ElementDatabase.get_element(element_id)
	if element_data.is_empty():
		return false

	var conditions: Dictionary = element_data.get(&"carrier_risk_conditions", {})
	if not conditions is Dictionary:
		return false

	var hp_threshold := float(conditions.get(&"hp_threshold", -1.0))
	if hp_threshold >= 0.0 and float(GameManager.player_health) <= float(GameManager.max_player_health) * hp_threshold:
		return true

	var status_trigger := StringName(str(conditions.get(&"status_trigger", "")))
	if not status_trigger.is_empty() and GameManager.player_status_effects.has(status_trigger):
		return true

	return false


func _process_lithium_exposure() -> void:
	if not InventoryManager.has_item(LITHIUM_ITEM_ID):
		_lithium_exposure_elapsed = 0.0
		_reset_countdown(LITHIUM_ITEM_ID)
		return

	if not _is_lithium_exposed():
		_lithium_exposure_elapsed = 0.0
		_reset_countdown(LITHIUM_ITEM_ID)
		return

	_lithium_exposure_elapsed += CHECK_INTERVAL_SECONDS
	if _lithium_exposure_elapsed < LITHIUM_DEGRADE_INTERVAL_SECONDS:
		return

	while _lithium_exposure_elapsed >= LITHIUM_DEGRADE_INTERVAL_SECONDS:
		_lithium_exposure_elapsed -= LITHIUM_DEGRADE_INTERVAL_SECONDS
		var current_charge := InventoryManager.get_item_charge(LITHIUM_ITEM_ID)
		var next_charge := InventoryManager.drain_lithium_charge(LITHIUM_CHARGE_LOSS_PER_SECOND)
		var seconds_remaining := maxi(int(ceili(next_charge / LITHIUM_CHARGE_LOSS_PER_SECOND)), 0)

		if not _countdowns.has(LITHIUM_ITEM_ID):
			_countdowns[LITHIUM_ITEM_ID] = {
				&"elapsed": 0.0,
				&"last_emitted_second": seconds_remaining + 1,
			}

		var lithium_countdown: Dictionary = _countdowns[LITHIUM_ITEM_ID]
		var last_emitted_second := int(lithium_countdown.get(&"last_emitted_second", seconds_remaining + 1))
		if seconds_remaining > 0 and seconds_remaining != last_emitted_second:
			carrier_risk_warning.emit(LITHIUM_ITEM_ID, seconds_remaining)
			lithium_countdown[&"last_emitted_second"] = seconds_remaining

		lithium_countdown[&"elapsed"] = float(lithium_countdown.get(&"elapsed", 0.0)) + LITHIUM_DEGRADE_INTERVAL_SECONDS
		_countdowns[LITHIUM_ITEM_ID] = lithium_countdown

		if current_charge > 0.0 and next_charge <= 0.0:
			_lithium_exposure_elapsed = 0.0
			_trigger_lithium_explosion()
			return


func _is_lithium_exposed() -> bool:
	if is_sheltered():
		return false

	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var player := scene_root.find_child("Player", true, false) as Node2D
	if player == null:
		return false

	var weather_system := get_node_or_null("/root/WeatherSystem")

	if GameManager.active_environmental_warnings.has(&"rain"):
		if weather_system != null and weather_system.has_method("get_shelter_at"):
			if bool(weather_system.call("get_shelter_at", player.global_position)):
				return false
		if scene_root != null and scene_root.has_method("is_rain_blocked_at_world_position"):
			return not bool(scene_root.call("is_rain_blocked_at_world_position", player.global_position))
		return true

	if scene_root != null and scene_root.has_method("is_water_at_world_position"):
		return bool(scene_root.call("is_water_at_world_position", player.global_position))

	return false


func get_active_risk_reason(element_id: StringName) -> String:
	if element_id == LITHIUM_ITEM_ID:
		if is_sheltered():
			return ""
		if GameManager.active_environmental_warnings.has(&"rain"):
			var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
			var player := scene_root.find_child("Player", true, false) as Node2D
			var weather_system := get_node_or_null("/root/WeatherSystem")
			if player != null and weather_system != null and weather_system.has_method("get_shelter_at"):
				if bool(weather_system.call("get_shelter_at", player.global_position)):
					return ""
			if player != null and scene_root != null and scene_root.has_method("is_rain_blocked_at_world_position"):
				if not bool(scene_root.call("is_rain_blocked_at_world_position", player.global_position)):
					return "Lithium is decaying because it started raining."
			else:
				return "Lithium is decaying because it started raining."
				
		var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		var player := scene_root.find_child("Player", true, false) as Node2D
		if player != null and scene_root != null and scene_root.has_method("is_water_at_world_position"):
			if bool(scene_root.call("is_water_at_world_position", player.global_position)):
				return "Lithium is decaying because you are in water."
		return ""

	if bool(_external_triggers.get(element_id, false)):
		return str(_external_trigger_reasons.get(element_id, ""))

	var element_data: Dictionary = ElementDatabase.get_element(element_id)
	if element_data.is_empty():
		return ""

	var conditions: Dictionary = element_data.get(&"carrier_risk_conditions", {})
	if not conditions is Dictionary:
		return ""

	var hp_threshold := float(conditions.get(&"hp_threshold", -1.0))
	if hp_threshold >= 0.0 and float(GameManager.player_health) <= float(GameManager.max_player_health) * hp_threshold:
		return "Material is igniting because your health is critically low (<= %d%%)." % int(hp_threshold * 100)

	var status_trigger := StringName(str(conditions.get(&"status_trigger", "")))
	if not status_trigger.is_empty() and GameManager.player_status_effects.has(status_trigger):
		return "Material is igniting because you are %s." % status_trigger

	return ""


func set_external_trigger(element_id: StringName, active: bool, reason: String = "") -> void:
	if element_id.is_empty():
		return
	if active:
		_external_triggers[element_id] = true
		if not reason.is_empty():
			_external_trigger_reasons[element_id] = reason
		return
	_external_triggers.erase(element_id)
	_external_trigger_reasons.erase(element_id)

func set_sheltered(source_or_state, sheltered_state: bool = true) -> void:
	if source_or_state is bool:
		_set_shelter_source(-1, bool(source_or_state))
		return
	_set_shelter_source(int(source_or_state), sheltered_state)


func is_sheltered() -> bool:
	return not _shelter_sources.is_empty()


func _set_shelter_source(source_id: int, sheltered: bool) -> void:
	if sheltered:
		_shelter_sources[source_id] = true
	else:
		_shelter_sources.erase(source_id)


func _advance_countdown(element_id: StringName) -> void:
	if not _countdowns.has(element_id):
		_countdowns[element_id] = {
			&"elapsed": 0.0,
			&"last_emitted_second": 4,
		}

	var countdown: Dictionary = _countdowns[element_id]
	var elapsed := float(countdown.get(&"elapsed", 0.0)) + CHECK_INTERVAL_SECONDS
	var seconds_remaining := maxi(int(ceili(WARNING_DURATION_SECONDS - elapsed)), 0)
	var last_emitted_second := int(countdown.get(&"last_emitted_second", 4))

	if seconds_remaining > 0 and seconds_remaining != last_emitted_second:
		carrier_risk_warning.emit(element_id, seconds_remaining)
		countdown[&"last_emitted_second"] = seconds_remaining

	countdown[&"elapsed"] = elapsed
	_countdowns[element_id] = countdown

	if elapsed >= WARNING_DURATION_SECONDS:
		_trigger_ignition(element_id)


func _reset_countdown(element_id: StringName, emit_cleared: bool = true) -> void:
	if emit_cleared and _countdowns.has(element_id):
		var countdown: Dictionary = _countdowns[element_id]
		if float(countdown.get(&"elapsed", 0.0)) > 0.0:
			carrier_risk_cleared.emit(element_id)
	_countdowns.erase(element_id)


func _trigger_ignition(element_id: StringName) -> void:
	_reset_countdown(element_id, false)
	var quantity := InventoryManager.get_quantity(element_id)
	if quantity > 0:
		InventoryManager.remove_item(element_id, quantity)

	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var player := scene_root.find_child("Player", true, false)
	if player is Node2D:
		var explosion: Node2D = CHEMICAL_EXPLOSION_SCENE.instantiate()
		scene_root.add_child(explosion)
		explosion.global_position = (player as Node2D).global_position

	carrier_risk_ignition.emit(element_id)


func _trigger_lithium_explosion() -> void:
	_reset_countdown(LITHIUM_ITEM_ID, false)
	var quantity := InventoryManager.get_quantity(LITHIUM_ITEM_ID)
	if quantity > 0:
		InventoryManager.remove_item(LITHIUM_ITEM_ID, quantity)

	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var player := scene_root.find_child("Player", true, false)
	if player is Node2D:
		var explosion: Node2D = CHEMICAL_EXPLOSION_SCENE.instantiate()
		explosion.set("damage_radius_pixels", LITHIUM_EXPLOSION_RADIUS_PIXELS)
		explosion.set("damage_amount", LITHIUM_EXPLOSION_DAMAGE)
		explosion.set("damage_type", "explosion")
		explosion.set("destroy_inventory_slot", false)
		scene_root.add_child(explosion)
		explosion.global_position = (player as Node2D).global_position

	carrier_risk_ignition.emit(LITHIUM_ITEM_ID)
