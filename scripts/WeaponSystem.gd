class_name WeaponSystem
extends Node

## WeaponSystem
## Holds equipped weapon state and interacts with DamageCalculator.

var equipped_weapon: Dictionary = {}

func equip_weapon(weapon_data: Dictionary) -> void:
	equipped_weapon = weapon_data
	print("Equipped weapon: ", equipped_weapon.get("display_name", "Unknown"))

func unequip_weapon() -> void:
	equipped_weapon.clear()
	print("Weapon unequipped")

func fire(target: Node) -> void:
	if equipped_weapon.is_empty():
		print("No weapon equipped!")
		return
	
	# Assuming a DamageCalculator autoload or class will be implemented later
	if ClassDB.class_exists("DamageCalculator") or has_node("/root/DamageCalculator"):
		# DamageCalculator.calculate_and_apply(equipped_weapon, target)
		pass
	else:
		print("Fired weapon: ", equipped_weapon.get("display_name", "Unknown"), " at ", target.name)
