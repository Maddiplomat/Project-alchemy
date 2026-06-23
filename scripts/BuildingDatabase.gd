extends Node

const BUILDABLE_ORDER: Array[StringName] = [
	&"wall",
	&"door",
	&"furnace",
	&"chem_bench",
	&"campfire",
	&"storage_chest",
	&"volatile_locker",
	&"dry_box",
	&"shelter_roof",
	&"powered_light_post",
	&"electric_trap",
]

const CATEGORY_LABELS := {
	&"structure": "Structures",
	&"station": "Stations",
	&"storage": "Storage",
	&"defense": "Defense",
}

const BUILDABLE_REGISTRY := {
	&"wall": {
		&"scene_path": "res://scenes/Wall.tscn",
		&"prefab": preload("res://scenes/Wall.tscn"),
		&"cost": {&"stone": 2},
		&"label": "Wall",
		&"category": &"structure",
		&"description": "Basic structural support for base layouts and roof anchors.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {},
	},
	&"door": {
		&"scene_path": "res://scenes/Door.tscn",
		&"prefab": preload("res://scenes/Door.tscn"),
		&"cost": {&"wood": 1, &"stone": 1},
		&"label": "Door",
		&"category": &"structure",
		&"description": "Traversable opening for enclosed structures.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {},
	},
	&"furnace": {
		&"scene_path": "res://scenes/FurnacePlaced.tscn",
		&"prefab": preload("res://scenes/FurnacePlaced.tscn"),
		&"cost": {&"iron": 3, &"stone": 2},
		&"label": "Furnace",
		&"category": &"station",
		&"description": "Heat, fuel, and smelting station for charcoal and metallurgy.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {},
	},
	&"chem_bench": {
		&"scene_path": "res://scenes/ChemBenchPlaced.tscn",
		&"prefab": preload("res://scenes/ChemBenchPlaced.tscn"),
		&"cost": {&"iron": 4, &"wood": 2},
		&"label": "Chem Bench",
		&"category": &"station",
		&"description": "Bench for reactive recipes, stabilization, and sulfur chemistry.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {
			&"entry_id": &"chem_bench_access",
			&"locked_name": "Sealed Chem Bench Plans",
			&"hint": "Discover steel to unlock chem bench construction.",
		},
	},
	&"campfire": {
		&"scene_path": "res://scenes/Campfire.tscn",
		&"prefab": preload("res://scenes/Campfire.tscn"),
		&"cost": {&"wood": 5},
		&"label": "Campfire",
		&"category": &"station",
		&"description": "Starter heat source and recovery point.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {},
	},
	&"storage_chest": {
		&"scene_path": "res://scenes/StorageChest.tscn",
		&"prefab": preload("res://scenes/StorageChest.tscn"),
		&"cost": {&"wood": 4},
		&"label": "Storage Chest",
		&"category": &"storage",
		&"description": "General storage for base overflow and crafted goods.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {},
	},
	&"volatile_locker": {
		&"scene_path": "res://scenes/buildings/VolatileLocker.tscn",
		&"prefab": preload("res://scenes/buildings/VolatileLocker.tscn"),
		&"cost": {&"iron": 2, &"wood": 3},
		&"label": "Volatile Locker",
		&"category": &"storage",
		&"description": "Dry storage for volatile reagents you do not want to carry.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {
			&"entry_id": &"sulfur_storage",
			&"locked_name": "Volatile Locker",
			&"hint": "Complete a sulfur run to unlock dedicated volatile storage.",
		},
	},
	&"dry_box": {
		&"scene_path": "res://scenes/buildings/DryBox.tscn",
		&"prefab": preload("res://scenes/buildings/DryBox.tscn"),
		&"cost": {&"wood": 3, &"limestone": 2},
		&"label": "Dry Box",
		&"category": &"storage",
		&"description": "Weather-safe storage for water-reactive materials such as lithium.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {
			&"entry_id": &"dry_box_access",
			&"locked_name": "Dry Box",
			&"hint": "Recover lithium to unlock weather-safe dry storage.",
		},
	},
	&"shelter_roof": {
		&"scene_path": "res://scenes/buildings/ShelterRoof.tscn",
		&"prefab": preload("res://scenes/buildings/ShelterRoof.tscn"),
		&"cost": {&"wood": 4, &"stone": 2},
		&"label": "Shelter Roof",
		&"category": &"structure",
		&"description": "Rain cover for a 3x3 area. Needs two adjacent walls or doors for support.",
		&"overlay": true,
		&"rotatable": false,
		&"discovery_gate": {},
	},
	&"powered_light_post": {
		&"scene_path": "res://scenes/PoweredLightPost.tscn",
		&"prefab": preload("res://scenes/PoweredLightPost.tscn"),
		&"cost": {&"iron": 1, &"energy_cell": 1},
		&"label": "Powered Light",
		&"category": &"defense",
		&"description": "Perimeter lighting tied to the base power grid.",
		&"overlay": false,
		&"rotatable": false,
		&"discovery_gate": {
			&"entry_id": &"base_power_online",
			&"locked_name": "Powered Light",
			&"hint": "Charge the base grid at the Battery Station to unlock powered defenses.",
		},
	},
	&"electric_trap": {
		&"scene_path": "res://scenes/ElectricTrap.tscn",
		&"prefab": preload("res://scenes/ElectricTrap.tscn"),
		&"cost": {&"iron": 2, &"lithium": 1, &"energy_cell": 1},
		&"label": "Electric Trap",
		&"category": &"defense",
		&"description": "Directional powered defense that can short under bad weather.",
		&"overlay": false,
		&"rotatable": true,
		&"discovery_gate": {
			&"entry_id": &"base_power_online",
			&"locked_name": "Electric Trap",
			&"hint": "Charge the base grid at the Battery Station to unlock powered defenses.",
		},
	},
}


func get_buildable_order() -> Array[StringName]:
	return BUILDABLE_ORDER.duplicate()


func get_buildable_ids(include_locked: bool = true) -> Array[StringName]:
	var result: Array[StringName] = []
	for buildable_id: StringName in BUILDABLE_ORDER:
		if not has_buildable(buildable_id):
			continue
		if not include_locked and not is_buildable_unlocked(buildable_id):
			continue
		result.append(buildable_id)
	return result


func has_buildable(buildable_id: StringName) -> bool:
	return BUILDABLE_REGISTRY.has(buildable_id)


func get_buildable_entry(buildable_id: StringName) -> Dictionary:
	if not BUILDABLE_REGISTRY.has(buildable_id):
		return {}
	return (BUILDABLE_REGISTRY[buildable_id] as Dictionary).duplicate(true)


func get_category_label(category_id: StringName) -> String:
	return str(CATEGORY_LABELS.get(category_id, String(category_id).capitalize()))


func is_buildable_unlocked(buildable_id: StringName) -> bool:
	var gate := get_buildable_gate(buildable_id)
	if gate.is_empty():
		return true
	var entry_id := StringName(gate.get(&"entry_id", &""))
	if entry_id.is_empty():
		return true
	if DiscoveryLog != null and DiscoveryLog.has_method("has_discovery"):
		return bool(DiscoveryLog.has_discovery(entry_id))
	return true


func get_buildable_gate_hint(buildable_id: StringName) -> String:
	return str(get_buildable_gate(buildable_id).get(&"hint", ""))


func get_buildable_locked_name(buildable_id: StringName) -> String:
	return str(get_buildable_gate(buildable_id).get(&"locked_name", "???"))


func get_buildable_gate(buildable_id: StringName) -> Dictionary:
	return get_buildable_entry(buildable_id).get(&"discovery_gate", {}) as Dictionary
