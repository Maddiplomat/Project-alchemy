class_name WeaponSystem
extends Node

## WeaponSystem
## Holds equipped weapon state and interacts with DamageCalculator.

var equipped_weapon: Dictionary = {}

func equip_weapon(weapon_data: Dictionary) -> void:
	equipped_weapon = weapon_data
	DebugLog.info("Equipped weapon: %s" % equipped_weapon.get("display_name", "Unknown"))

func unequip_weapon() -> void:
	equipped_weapon.clear()
	DebugLog.info("Weapon unequipped")

func fire(target: Node) -> void:
	if equipped_weapon.is_empty():
		DebugLog.info("No weapon equipped")
		return
	
	# Assuming a DamageCalculator autoload or class will be implemented later
	if ClassDB.class_exists("DamageCalculator") or has_node("/root/DamageCalculator"):
		# DamageCalculator.calculate_and_apply(equipped_weapon, target)
		pass
	else:
		DebugLog.info(
			"Fired weapon: %s at %s"
			% [equipped_weapon.get("display_name", "Unknown"), target.name]
		)
