class_name DamageCalculator
extends RefCounted

## DamageCalculator
## Static class to resolve final damage considering resistances.

const DAMAGE_NUMBER_SCENE := preload("res://scenes/DamageNumber.tscn")

static func get_multiplier(damage_type: StringName, target: Node) -> float:
	var multiplier := 1.0

	if target and "resistances" in target:
		var resistances = target.get("resistances")
		if resistances is Dictionary and resistances.has(damage_type):
			multiplier = float(resistances[damage_type])

	return multiplier


static func calculate(base_damage: float, damage_type: StringName, target: Node, impact_position = null) -> float:
	var multiplier := get_multiplier(damage_type, target)
	var final_damage := maxf(0.0, base_damage * multiplier)
	_spawn_damage_number(final_damage, damage_type, target, impact_position)
	return final_damage


static func _spawn_damage_number(amount: float, damage_type: StringName, target: Node, impact_position) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or DAMAGE_NUMBER_SCENE == null:
		return

	var spawn_position: Variant = _resolve_spawn_position(target, impact_position)
	if spawn_position == null:
		return

	var damage_number := DAMAGE_NUMBER_SCENE.instantiate()
	if damage_number == null:
		return

	tree.current_scene.add_child(damage_number)
	damage_number.global_position = spawn_position
	if damage_number.has_method("setup"):
		damage_number.setup(amount, damage_type if amount > 0.0 else &"immune")


static func _resolve_spawn_position(target: Node, impact_position) -> Variant:
	if impact_position is Vector2:
		return impact_position + Vector2(0.0, -16.0)

	var current: Node = target
	while current != null:
		if current is Node2D:
			return current.global_position + Vector2(0.0, -16.0)
		current = current.get_parent()

	return null
