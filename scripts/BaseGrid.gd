extends Node

signal power_activated
signal power_deactivated
signal charge_level_changed(current_charge: float, max_charge: float)

const MAX_CHARGE: float = 60.0
const DRAIN_PER_SECOND: float = 1.0 / 60.0

var charge_level: float = 0.0
var _is_powered: bool = false


func _process(delta: float) -> void:
	if charge_level > 0.0:
		charge_level = maxf(0.0, charge_level - DRAIN_PER_SECOND * delta)
		charge_level_changed.emit(charge_level, MAX_CHARGE)
		
		if charge_level <= 0.0 and _is_powered:
			_is_powered = false
			power_deactivated.emit()


func add_charge(amount: float) -> void:
	if amount <= 0.0:
		return
		
	var was_powered := _is_powered
	charge_level = minf(MAX_CHARGE, charge_level + amount)
	
	if charge_level > 0.0:
		_is_powered = true
		
	charge_level_changed.emit(charge_level, MAX_CHARGE)
	
	if not was_powered and _is_powered:
		power_activated.emit()


func is_powered() -> bool:
	return _is_powered


func get_charge_percentage() -> float:
	return charge_level / MAX_CHARGE
