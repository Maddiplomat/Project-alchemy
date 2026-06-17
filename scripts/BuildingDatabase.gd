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

const BUILDABLE_REGISTRY := {
	&"wall": {
		&"prefab": preload("res://scenes/Wall.tscn"),
		&"cost": {&"stone": 2},
		&"label": "Wall",
	},
	&"door": {
		&"prefab": preload("res://scenes/Door.tscn"),
		&"cost": {&"wood": 1, &"stone": 1},
		&"label": "Door",
	},
	&"furnace": {
		&"prefab": preload("res://scenes/FurnacePlaced.tscn"),
		&"cost": {&"iron": 3, &"stone": 2},
		&"label": "Furnace",
	},
	&"chem_bench": {
		&"prefab": preload("res://scenes/ChemBenchPlaced.tscn"),
		&"cost": {&"iron": 4, &"wood": 2},
		&"label": "Chem Bench",
	},
	&"campfire": {
		&"prefab": preload("res://scenes/Campfire.tscn"),
		&"cost": {&"wood": 5},
		&"label": "Campfire",
	},
	&"storage_chest": {
		&"prefab": preload("res://scenes/StorageChest.tscn"),
		&"cost": {&"wood": 4},
		&"label": "Storage Chest",
	},
	&"volatile_locker": {
		&"prefab": preload("res://scenes/buildings/VolatileLocker.tscn"),
		&"cost": {&"iron": 2, &"wood": 3},
		&"label": "Volatile Locker",
	},
	&"dry_box": {
		&"prefab": preload("res://scenes/buildings/DryBox.tscn"),
		&"cost": {&"wood": 3, &"limestone": 2},
		&"label": "Dry Box",
	},
	&"shelter_roof": {
		&"prefab": preload("res://scenes/buildings/ShelterRoof.tscn"),
		&"cost": {&"wood": 4, &"stone": 2},
		&"label": "Shelter Roof",
		&"overlay": true,
	},
	&"powered_light_post": {
		&"prefab": preload("res://scenes/PoweredLightPost.tscn"),
		&"cost": {&"iron": 1, &"energy_cell": 1},
		&"label": "Powered Light",
	},
	&"electric_trap": {
		&"prefab": preload("res://scenes/ElectricTrap.tscn"),
		&"cost": {&"iron": 2, &"lithium": 1, &"energy_cell": 1},
		&"label": "Electric Trap",
		&"rotatable": true,
	},
}


func get_buildable_order() -> Array[StringName]:
	return BUILDABLE_ORDER.duplicate()


func has_buildable(buildable_id: StringName) -> bool:
	return BUILDABLE_REGISTRY.has(buildable_id)


func get_buildable_entry(buildable_id: StringName) -> Dictionary:
	if not BUILDABLE_REGISTRY.has(buildable_id):
		return {}
	return (BUILDABLE_REGISTRY[buildable_id] as Dictionary).duplicate(true)
