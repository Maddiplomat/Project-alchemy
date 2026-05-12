extends Node

signal health_changed(current: int, max: int)
signal player_died
signal status_effects_changed(status_effects: Array[StringName])

const DAMAGE_TYPE_PHYSICAL := &"physical"
const DAMAGE_TYPE_BURN := &"burn"
const DAMAGE_TYPE_TOXIC := &"toxic"
const DAMAGE_TYPE_RADIATION := &"radiation"
const VALID_DAMAGE_TYPES: Array[StringName] = [
	DAMAGE_TYPE_PHYSICAL,
	DAMAGE_TYPE_BURN,
	DAMAGE_TYPE_TOXIC,
	DAMAGE_TYPE_RADIATION,
]

@export var max_health: int = 100
@export var current_health: int = 100

var status_effects: Array[StringName] = []
var _is_dead := false


func _ready() -> void:
	max_health = max(1, max_health)
	current_health = clampi(current_health, 0, max_health)
	GameManager.bind_player_health_system(self)
	_emit_state()


func take_damage(amount: int, type: StringName = DAMAGE_TYPE_PHYSICAL) -> void:
	if amount <= 0 or _is_dead:
		return

	if InventoryManager.is_over_capacity():
		amount = int(float(amount) * 1.5)

	var damage_type := _normalize_damage_type(type)
	match damage_type:
		DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_BURN, DAMAGE_TYPE_TOXIC, DAMAGE_TYPE_RADIATION:
			current_health = clampi(current_health - amount, 0, max_health)

	if current_health <= 0:
		die()
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


func die() -> void:
	if _is_dead:
		return

	_is_dead = true
	current_health = 0
	health_changed.emit(current_health, max_health)
	GameManager.mark_dirty()
	player_died.emit()


func reset_state() -> void:
	_is_dead = false
	current_health = max_health
	clear_status_effects()
	health_changed.emit(current_health, max_health)


func add_status_effect(effect: StringName) -> void:
	if effect.is_empty() or status_effects.has(effect):
		return

	status_effects.append(effect)
	status_effects_changed.emit(status_effects.duplicate())
	GameManager.mark_dirty()


func remove_status_effect(effect: StringName) -> void:
	var effect_index := status_effects.find(effect)
	if effect_index == -1:
		return

	status_effects.remove_at(effect_index)
	status_effects_changed.emit(status_effects.duplicate())
	GameManager.mark_dirty()


func clear_status_effects() -> void:
	if status_effects.is_empty():
		return

	status_effects.clear()
	status_effects_changed.emit(status_effects.duplicate())
	GameManager.mark_dirty()


func _emit_state() -> void:
	health_changed.emit(current_health, max_health)
	status_effects_changed.emit(status_effects.duplicate())


func _normalize_damage_type(type: StringName) -> StringName:
	if VALID_DAMAGE_TYPES.has(type):
		return type
	return DAMAGE_TYPE_PHYSICAL
