extends "res://scripts/Furnace.gd"

@export var object_type := "furnace"
@export var placed_at := Vector2i.ZERO


func _ready() -> void:
	add_to_group(&"placed_objects")
	add_to_group(&"placed_stations")
	super()


func configure_placed_object(tile_coords: Vector2i) -> void:
	placed_at = tile_coords
	set_meta(&"placed_object", true)
	set_meta(&"build_tile_coords", tile_coords)
	set_meta(&"object_type", object_type)


func to_world_save_entry() -> Dictionary:
	return {
		&"object_type": object_type,
		&"placed_at": placed_at,
		&"scene_path": scene_file_path,
		&"power_state": get_power_state(),
	}


func restore_from_pickup(data: Dictionary) -> void:
	restore_power_state(data.get(&"power_state", {}))


func export_to_world_save_data(world_save_data) -> void:
	if world_save_data == null:
		return
	world_save_data.add_placed_station(to_world_save_entry())
