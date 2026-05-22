extends Node

const HealthSystemScript = preload("res://scripts/HealthSystem.gd")


func _ready() -> void:
	await _run_simulation()
	get_tree().quit()


func _run_simulation() -> void:
	var oxidation_target = _spawn_health_system({
		&"oxidation": 3.0,
	})
	var blunt_target = _spawn_health_system({
		&"physical_blunt": 0.0,
	})

	await get_tree().process_frame

	_simulate_hit(oxidation_target, 18, &"oxidation", 3.0, 54, 46)
	_simulate_hit(blunt_target, 10, &"physical_blunt", 0.0, 0, 100)

	print("CombatDamageSimulation completed successfully.")


func _spawn_health_system(resistances: Dictionary) -> Node:
	var health_system = HealthSystemScript.new()
	health_system.max_health = 100
	health_system.current_health = 100
	health_system.resistances = resistances
	add_child(health_system)
	return health_system


func _simulate_hit(
	health_system: Node,
	base_damage: int,
	damage_type: StringName,
	expected_multiplier: float,
	expected_effective_damage: int,
	expected_health: int
) -> void:
	var resolved_multiplier := DamageCalculator.get_multiplier(damage_type, health_system)
	var resolved_damage := int(DamageCalculator.calculate(float(base_damage), damage_type, health_system))
	print(
		"CombatDamageSimulation multiplier: type=%s base=%d multiplier=%.2f effective=%d"
		% [String(damage_type), base_damage, resolved_multiplier, resolved_damage]
	)

	if not is_equal_approx(resolved_multiplier, expected_multiplier):
		push_error(
			"Unexpected multiplier for %s: expected %.2f, got %.2f"
			% [String(damage_type), expected_multiplier, resolved_multiplier]
		)
	if resolved_damage != expected_effective_damage:
		push_error(
			"Unexpected effective damage for %s: expected %d, got %d"
			% [String(damage_type), expected_effective_damage, resolved_damage]
		)

	health_system.take_damage(base_damage, damage_type)
	if health_system.current_health != expected_health:
		push_error(
			"Unexpected health after %s damage: expected %d, got %d"
			% [String(damage_type), expected_health, health_system.current_health]
		)
