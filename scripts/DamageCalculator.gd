class_name DamageCalculator
extends RefCounted

## DamageCalculator
## Static class to resolve final damage considering resistances.

static func get_multiplier(damage_type: StringName, target: Node) -> float:
	var multiplier := 1.0

	if target and "resistances" in target:
		var resistances = target.get("resistances")
		if resistances is Dictionary and resistances.has(damage_type):
			multiplier = float(resistances[damage_type])

	return multiplier


static func calculate(base_damage: float, damage_type: StringName, target: Node) -> float:
	var multiplier := get_multiplier(damage_type, target)
	var final_damage := maxf(0.0, base_damage * multiplier)
	return final_damage
