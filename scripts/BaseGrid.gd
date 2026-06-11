extends Node

signal power_activated
signal power_deactivated
signal charge_level_changed(current_charge: float, max_charge: float)

const MAX_CHARGE: float = 30.0
const CHARGE_PER_CELL: float = 20.0

var charge_level: float = 0.0
var _is_powered: bool = false


func _process(delta: float) -> void:
	if charge_level <= 0.0:
		return
	if BaseDefenseSystem == null or not BaseDefenseSystem.has_method("get_total_drain_per_second"):
		return

	var current_drain := float(BaseDefenseSystem.get_total_drain_per_second())
	if current_drain <= 0.0:
		return

	charge_level = maxf(0.0, charge_level - current_drain * delta)
	_sync_power_state()


func add_charge(amount: float) -> void:
	if amount <= 0.0:
		return
	charge_level = minf(MAX_CHARGE, charge_level + amount)
	_sync_power_state()


func add_charge_cell() -> void:
	add_charge(CHARGE_PER_CELL)


func consume_charge(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if charge_level < amount:
		return false
	charge_level = maxf(0.0, charge_level - amount)
	_sync_power_state()
	return true


func is_powered() -> bool:
	return _is_powered


func get_charge_percentage() -> float:
	return charge_level / MAX_CHARGE if MAX_CHARGE > 0.0 else 0.0


func get_charge_state() -> float:
	return charge_level


func restore_charge_level(value: float) -> void:
	charge_level = clampf(value, 0.0, MAX_CHARGE)
	_sync_power_state()


func _sync_power_state() -> void:
	var was_powered := _is_powered
	_is_powered = charge_level > 0.0
	charge_level_changed.emit(charge_level, MAX_CHARGE)
	if not was_powered and _is_powered:
		power_activated.emit()
	elif was_powered and not _is_powered:
		power_deactivated.emit()
