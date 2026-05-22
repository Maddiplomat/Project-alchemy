class_name DamageCalculator
extends RefCounted

## DamageCalculator
## Static class to resolve final damage considering resistances.

static func calculate(base_damage: float, damage_type: String, target: Node) -> float:
	var multiplier := 1.0
	
	if target and "resistances" in target:
		var resistances = target.get("resistances")
		if resistances is Dictionary and resistances.has(damage_type):
			multiplier = float(resistances[damage_type])
			
	var final_damage := maxf(0.0, base_damage * multiplier)
	return final_damage
