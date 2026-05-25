extends Node

signal carrier_risk_warning(element_id: StringName, seconds_remaining: int)
signal carrier_risk_cleared(element_id: StringName)
signal carrier_risk_ignition(element_id: StringName)

const CHECK_INTERVAL_SECONDS := 0.5
const WARNING_DURATION_SECONDS := 3.0
const CHEMICAL_EXPLOSION_SCENE := preload("res://scenes/ChemicalExplosion.tscn")

var _check_timer: Timer = null
var _countdowns: Dictionary = {}


func _ready() -> void:
	_check_timer = Timer.new()
	_check_timer.wait_time = CHECK_INTERVAL_SECONDS
	_check_timer.one_shot = false
	_check_timer.timeout.connect(_on_check_timeout)
	add_child(_check_timer)
	_check_timer.start()


func _on_check_timeout() -> void:
	var active_volatile_items := _get_active_volatile_items()
	var active_item_lookup: Dictionary = {}
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
		var element_data: Dictionary = ElementDatabase.get_element(item_id)
		if element_data.is_empty():
			continue
		if String(element_data.get(&"category", "")).to_lower() != "volatile":
			continue
		volatile_items.append(item_id)
	return volatile_items


func _should_trigger_risk_for(element_id: StringName) -> bool:
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
