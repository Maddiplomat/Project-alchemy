class_name PlacedObject
extends StaticBody2D

enum SaveBucket { STATIONS, WALLS, STORAGE }

@export var object_type := ""
@export var placed_at := Vector2i.ZERO
@export var save_bucket := SaveBucket.STATIONS

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group(&"placed_objects")
	match save_bucket:
		SaveBucket.STATIONS:
			add_to_group(&"placed_stations")
		SaveBucket.WALLS:
			add_to_group(&"placed_walls")
		SaveBucket.STORAGE:
			add_to_group(&"placed_storage")


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
		&"placed_rotation_degrees": rotation_degrees,
	}


func get_occupied_tile_coords() -> Array[Vector2i]:
	return [placed_at]


func export_to_world_save_data(world_save_data) -> void:
	if world_save_data == null:
		return

	match save_bucket:
		SaveBucket.STATIONS:
			world_save_data.add_placed_station(to_world_save_entry())
		SaveBucket.WALLS:
			world_save_data.add_wall(to_world_save_entry())
		SaveBucket.STORAGE:
			world_save_data.add_storage(to_world_save_entry())
