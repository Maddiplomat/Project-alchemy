extends Node2D

const MAP_SIZE := Vector2i(64, 64)
const TILE_SIZE := 16
const SOURCE_ID := 0
const GRASS_TILE := Vector2i(0, 0)
const TREE_TILE := Vector2i(1, 1)
const ROCK_TILE := Vector2i(2, 1)
const WATER_TILE := Vector2i(3, 0)
const SPARSE_TREE_MIN := 0.3
const DENSE_TREE_MIN := 0.6
const ELEMENT_SPAWN_SYSTEM_SCRIPT := preload("res://scripts/ElementSpawn.gd")

var _river_tile_coords: Array[Vector2i] = []

@export var generate_on_ready := true
@export var noise_frequency := 0.08
@export_range(0.0, 1.0, 0.01) var sparse_tree_density := 0.35

@onready var ground_layer: TileMapLayer = $Ground
@onready var decor_layer: TileMapLayer = $Decor
@onready var objects_layer: TileMapLayer = $Objects
@onready var element_spawn_system := get_node_or_null("ElementSpawnSystem") as Node2D


func _ready() -> void:
	_prepare_element_spawn_system()
	if generate_on_ready:
		generate_world(_get_world_seed())
	_wire_camera_bounds()


func generate_world(world_seed: int) -> void:
	_set_world_seed(world_seed)
	_clear_layers()

	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = noise_frequency

	for y in range(MAP_SIZE.y):
		for x in range(MAP_SIZE.x):
			var coords := Vector2i(x, y)
			ground_layer.set_cell(coords, SOURCE_ID, GRASS_TILE, 0)

			if _is_edge(coords):
				objects_layer.set_cell(coords, SOURCE_ID, ROCK_TILE, 0)
				continue

			if _is_spawn_area(coords):
				continue

			var noise_value := _normalized_noise(noise, coords)
			if noise_value >= DENSE_TREE_MIN:
				objects_layer.set_cell(coords, SOURCE_ID, TREE_TILE, 0)
			elif noise_value >= SPARSE_TREE_MIN and _passes_sparse_tree_roll(world_seed, coords):
				objects_layer.set_cell(coords, SOURCE_ID, TREE_TILE, 0)

	_place_river_cluster(world_seed)
	_spawn_elements(world_seed)
	_spawn_water_pickups(world_seed)


func regenerate_with_seed(world_seed: int) -> void:
	generate_world(world_seed)


func _clear_layers() -> void:
	ground_layer.clear()
	decor_layer.clear()
	objects_layer.clear()
	_river_tile_coords.clear()


func _place_river_cluster(world_seed: int) -> void:
	_river_tile_coords.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 3571

	# Anchor the river to the lower-left quadrant, away from spawn centre
	var anchor := Vector2i(
		rng.randi_range(8, MAP_SIZE.x / 4),
		rng.randi_range(MAP_SIZE.y / 2, MAP_SIZE.y - 10)
	)

	# Carve a short river-edge strip of 10 water tiles in a loose horizontal band
	for i in range(10):
		var offset := Vector2i(i * 2, rng.randi_range(-1, 1))
		var coords := anchor + offset
		if _is_edge(coords):
			continue
		# Water goes on the ground layer; clear any object tile above it
		ground_layer.set_cell(coords, SOURCE_ID, WATER_TILE, 0)
		objects_layer.erase_cell(coords)
		_river_tile_coords.append(coords)


func _is_edge(coords: Vector2i) -> bool:
	return coords.x == 0 or coords.y == 0 or coords.x == MAP_SIZE.x - 1 or coords.y == MAP_SIZE.y - 1


func _is_spawn_area(coords: Vector2i) -> bool:
	var spawn_coords := Vector2i(MAP_SIZE.x >> 1, MAP_SIZE.y >> 1)
	return abs(coords.x - spawn_coords.x) <= 2 and abs(coords.y - spawn_coords.y) <= 2


func _normalized_noise(noise: FastNoiseLite, coords: Vector2i) -> float:
	return (noise.get_noise_2d(coords.x, coords.y) + 1.0) * 0.5


func _passes_sparse_tree_roll(world_seed: int, coords: Vector2i) -> bool:
	var roll := posmod(hash("%d:%d:%d" % [world_seed, coords.x, coords.y]), 10000) / 10000.0
	return roll < sparse_tree_density


func _prepare_element_spawn_system() -> void:
	if element_spawn_system == null:
		return

	if element_spawn_system.get_script() == null:
		element_spawn_system.set_script(ELEMENT_SPAWN_SYSTEM_SCRIPT)


func _spawn_elements(world_seed: int) -> void:
	_prepare_element_spawn_system()
	if element_spawn_system != null and element_spawn_system.has_method("spawn_elements"):
		element_spawn_system.spawn_elements(ground_layer, objects_layer, world_seed)


func _spawn_water_pickups(world_seed: int) -> void:
	if _river_tile_coords.is_empty():
		return
	_prepare_element_spawn_system()
	if element_spawn_system == null or not element_spawn_system.has_method("spawn_element_at"):
		_spawn_water_pickups_fallback(world_seed)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 4201
	var count := rng.randi_range(4, 6)
	var shuffled := _river_tile_coords.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	for i in range(mini(count, shuffled.size())):
		element_spawn_system.spawn_element_at(&"water", shuffled[i], ground_layer)


func _spawn_water_pickups_fallback(world_seed: int) -> void:
	if element_spawn_system == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 4201
	var count := rng.randi_range(4, 6)
	var shuffled := _river_tile_coords.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var pickup_scene: PackedScene = load("res://scenes/ElementPickup.tscn")
	if pickup_scene == null:
		return
	for i in range(mini(count, shuffled.size())):
		var coords := shuffled[i]
		var pickup := pickup_scene.instantiate()
		pickup.name = "water_%d_%d" % [coords.x, coords.y]
		pickup.set(&"element_id", &"water")
		pickup.set_meta(&"element_id", &"water")
		pickup.set_meta(&"tile_coords", coords)
		element_spawn_system.add_child(pickup)
		pickup.global_position = ground_layer.to_global(ground_layer.map_to_local(coords))


func _get_world_seed() -> int:
	var world_system := get_tree().root.get_node_or_null("WorldSystem")
	if world_system != null and world_system.has_method("get_seed"):
		return world_system.get_seed()
	return 0


func _set_world_seed(world_seed: int) -> void:
	var world_system := get_tree().root.get_node_or_null("WorldSystem")
	if world_system != null and world_system.has_method("set_seed"):
		world_system.set_seed(world_seed)


func get_world_bounds() -> Rect2:
	if ground_layer == null:
		return Rect2(Vector2.ZERO, Vector2(MAP_SIZE) * TILE_SIZE)
	var used_rect := ground_layer.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, Vector2(MAP_SIZE) * TILE_SIZE)
	return Rect2(
		used_rect.position.x * TILE_SIZE,
		used_rect.position.y * TILE_SIZE,
		used_rect.size.x * TILE_SIZE,
		used_rect.size.y * TILE_SIZE
	)


func _wire_camera_bounds() -> void:
	var camera := find_child("Camera2D", true, false) as Camera2D
	if camera != null:
		camera.set("bounds_source_path", get_path())
