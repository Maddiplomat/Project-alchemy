extends Node

## CombatSystem Autoload
## Manages registered damage types and combat states.

var _damage_types: Dictionary = {}

func _ready() -> void:
	_register_default_damage_types()

func _register_default_damage_types() -> void:
	register_damage_type("physical_sharp", "Piercing/Slashing", "#CCCCCC")
	register_damage_type("physical_blunt", "Bludgeoning", "#8B4513")
	register_damage_type("oxidation", "Oxidation/Fire", "#FF4500")
	register_damage_type("electrical", "Electrical", "#FFD700")
	register_damage_type("chemical", "Chemical/Acid", "#32CD32")
	register_damage_type("acid", "Acid", "#9ACD32")
	register_damage_type("radiation", "Radiation", "#00FF00")

func register_damage_type(id: String, display_name: String, color_hex: String) -> void:
	_damage_types[id] = {
		"id": id,
		"display_name": display_name,
		"color_hex": color_hex
	}

func get_damage_type(id: String) -> Dictionary:
	return _damage_types.get(id, {})
