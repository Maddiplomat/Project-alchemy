extends Node

const DebugLog = preload("res://scripts/DebugLog.gd")

signal health_changed(current: int, max: int)
signal player_died(cause_of_death: StringName)
signal status_effects_changed(status_effects: Array[StringName])

const DAMAGE_TYPE_PHYSICAL := &"physical"
const DAMAGE_TYPE_BURN := &"burn"
const DAMAGE_TYPE_TOXIC := &"toxic"
const DAMAGE_TYPE_RADIATION := &"radiation"
const DAMAGE_TYPE_EXPLOSION := &"explosion"
const DAMAGE_LOG_LIMIT := 5
const STATUS_EFFECT_BURNING := &"burning"
const STATUS_EFFECT_TOXIC := &"toxic"
const STATUS_TICK_INTERVAL_SECONDS := 1.0
const VALID_DAMAGE_TYPES: Array[StringName] = [
	DAMAGE_TYPE_PHYSICAL,
	DAMAGE_TYPE_BURN,
	DAMAGE_TYPE_TOXIC,
	DAMAGE_TYPE_RADIATION,
	DAMAGE_TYPE_EXPLOSION,
]

@export var max_health: int = 100
@export var current_health: int = 100
@export var over_capacity_damage_multiplier: float = 1.5
@export var resistances: Dictionary = {}

var status_effects: Array[StringName] = []
var damage_log: Array[Dictionary] = []
var _status_effect_runtime: Dictionary = {}
var _is_dead := false


func _ready() -> void:
	max_health = max(1, max_health)
	current_health = clampi(current_health, 0, max_health)
	GameManager.bind_player_health_system(self)
	set_process(true)
	_emit_state()


func _process(delta: float) -> void:
	if _is_dead or _status_effect_runtime.is_empty():
		return

	var expired_effects: Array[StringName] = []
	for effect: StringName in _status_effect_runtime.keys():
		var runtime: Dictionary = _status_effect_runtime[effect]
		runtime[&"remaining"] = maxf(float(runtime.get(&"remaining", 0.0)) - delta, 0.0)
		runtime[&"tick_timer"] = float(runtime.get(&"tick_timer", 0.0)) + delta

		while float(runtime.get(&"tick_timer", 0.0)) >= STATUS_TICK_INTERVAL_SECONDS and float(runtime.get(&"remaining", 0.0)) > 0.0:
			runtime[&"tick_timer"] = float(runtime.get(&"tick_timer", 0.0)) - STATUS_TICK_INTERVAL_SECONDS
			var damage_per_second := int(runtime.get(&"damage_per_second", 0))
			if damage_per_second > 0:
				take_resolved_damage(
					damage_per_second,
					StringName(runtime.get(&"damage_type", DAMAGE_TYPE_BURN)),
					String(runtime.get(&"source_label", "Burning"))
				)
				if _is_dead:
					return

		_status_effect_runtime[effect] = runtime
		if float(runtime.get(&"remaining", 0.0)) <= 0.0:
			expired_effects.append(effect)

	for effect: StringName in expired_effects:
		remove_status_effect(effect)


func take_damage(amount: int, type: StringName = DAMAGE_TYPE_PHYSICAL, source_label: String = "") -> void:
	if amount <= 0 or _is_dead:
		return

	var damage_type := _normalize_damage_type(type)
	var damage_multiplier := DamageCalculator.get_multiplier(damage_type, self)
	var final_amount: int = int(DamageCalculator.calculate(float(amount), damage_type, self))
	DebugLog.info(
		"HealthSystem damage multiplier: type=%s base=%d multiplier=%.2f effective=%d"
		% [String(damage_type), amount, damage_multiplier, final_amount]
	)

	if final_amount <= 0:
		return

	if InventoryManager.is_over_capacity():
		final_amount = int(float(final_amount) * over_capacity_damage_multiplier)

	_record_damage_event(final_amount, damage_type, source_label)
	current_health = clampi(current_health - final_amount, 0, max_health)

	if current_health <= 0:
		var cause_of_death := damage_type
		if damage_type == DAMAGE_TYPE_EXPLOSION:
			cause_of_death = StringName("Furnace overheated")
		die(cause_of_death)
		return

	health_changed.emit(current_health, max_health)
	GameManager.mark_dirty()


func take_resolved_damage(amount: int, type: StringName = DAMAGE_TYPE_PHYSICAL, source_label: String = "") -> void:
	if amount <= 0 or _is_dead:
		return

	var damage_type := _normalize_damage_type(type)
	var final_amount := amount
	if InventoryManager.is_over_capacity():
		final_amount = int(float(final_amount) * over_capacity_damage_multiplier)

	_record_damage_event(final_amount, damage_type, source_label)
	current_health = clampi(current_health - final_amount, 0, max_health)
	if current_health <= 0:
		var cause_of_death := damage_type
		if damage_type == DAMAGE_TYPE_EXPLOSION:
			cause_of_death = StringName("Furnace overheated")
		die(cause_of_death)
		return

	health_changed.emit(current_health, max_health)
	GameManager.mark_dirty()


func heal(amount: int) -> void:
	if amount <= 0 or _is_dead:
		return

	var previous_health := current_health
	current_health = clampi(current_health + amount, 0, max_health)
	if current_health == previous_health:
		return

	health_changed.emit(current_health, max_health)
	GameManager.mark_dirty()


func die(cause_of_death: StringName = DAMAGE_TYPE_PHYSICAL) -> void:
	if _is_dead:
		return

	_is_dead = true
	current_health = 0
	health_changed.emit(current_health, max_health)
	GameManager.mark_dirty()
	player_died.emit(cause_of_death)


func reset_state() -> void:
	_is_dead = false
	current_health = max_health
	damage_log.clear()
	_status_effect_runtime.clear()
	clear_status_effects()
	health_changed.emit(current_health, max_health)


func restore_state(saved_health: int, saved_status_effects: Array[StringName] = []) -> void:
	_is_dead = false
	# Death-triggered saves should still reload into a playable state.
	current_health = maxi(clampi(saved_health, 0, max_health), 1)
	damage_log.clear()
	_status_effect_runtime.clear()
	status_effects = saved_status_effects.duplicate()
	health_changed.emit(current_health, max_health)
	status_effects_changed.emit(status_effects.duplicate())


func add_status_effect(effect: StringName, damage_per_second: int = 0, duration_seconds: float = 0.0, source_label: String = "") -> void:
	if effect.is_empty():
		return

	if not status_effects.has(effect):
		status_effects.append(effect)
		status_effects_changed.emit(status_effects.duplicate())
		GameManager.mark_dirty()

	if duration_seconds > 0.0 or damage_per_second > 0:
		_status_effect_runtime[effect] = {
			&"remaining": duration_seconds,
			&"tick_timer": 0.0,
			&"damage_per_second": damage_per_second,
			&"damage_type": (
				DAMAGE_TYPE_BURN if effect == STATUS_EFFECT_BURNING else
				(DAMAGE_TYPE_TOXIC if effect == STATUS_EFFECT_TOXIC else DAMAGE_TYPE_PHYSICAL)
			),
			&"source_label": source_label if not source_label.strip_edges().is_empty() else String(effect).capitalize(),
		}


func remove_status_effect(effect: StringName) -> void:
	var effect_index := status_effects.find(effect)
	if effect_index == -1:
		return

	status_effects.remove_at(effect_index)
	_status_effect_runtime.erase(effect)
	status_effects_changed.emit(status_effects.duplicate())
	GameManager.mark_dirty()


func clear_status_effects() -> void:
	if status_effects.is_empty():
		return

	status_effects.clear()
	_status_effect_runtime.clear()
	status_effects_changed.emit(status_effects.duplicate())
	GameManager.mark_dirty()


func _emit_state() -> void:
	health_changed.emit(current_health, max_health)
	status_effects_changed.emit(status_effects.duplicate())


func _normalize_damage_type(type: StringName) -> StringName:
	if type.is_empty():
		return DAMAGE_TYPE_PHYSICAL
	return type


func get_recent_damage_entries(count: int = 3) -> Array[Dictionary]:
	var recent_entries: Array[Dictionary] = []
	if count <= 0:
		return recent_entries

	var start_index := maxi(damage_log.size() - count, 0)
	for index in range(start_index, damage_log.size()):
		recent_entries.append(damage_log[index].duplicate(true))
	return recent_entries


func _record_damage_event(amount: int, damage_type: StringName, source_label: String) -> void:
	var entry := {
		&"amount": amount,
		&"damage_type": damage_type,
		&"source_label": source_label.strip_edges(),
	}
	damage_log.append(entry)
	while damage_log.size() > DAMAGE_LOG_LIMIT:
		damage_log.remove_at(0)
