extends Node2D

const MAP_SIZE := Vector2i(64, 64)
const SOURCE_ID := 0
const GRASS_TILE := Vector2i(0, 0)
const TREE_TILE := Vector2i(1, 1)
const ROCK_TILE := Vector2i(2, 1)
const SPARSE_TREE_MIN := 0.3
const DENSE_TREE_MIN := 0.6
const ELEMENT_SPAWN_SYSTEM_SCRIPT := preload("res://scripts/ElementSpawn.gd")

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

			var noise_value := _normalized_noise(noise, coords)
			if noise_value >= DENSE_TREE_MIN:
				objects_layer.set_cell(coords, SOURCE_ID, TREE_TILE, 0)
			elif noise_value >= SPARSE_TREE_MIN and _passes_sparse_tree_roll(world_seed, coords):
				objects_layer.set_cell(coords, SOURCE_ID, TREE_TILE, 0)

	_spawn_elements(world_seed)


func regenerate_with_seed(world_seed: int) -> void:
	generate_world(world_seed)


func _clear_layers() -> void:
	ground_layer.clear()
	decor_layer.clear()
	objects_layer.clear()


func _is_edge(coords: Vector2i) -> bool:
	return coords.x == 0 or coords.y == 0 or coords.x == MAP_SIZE.x - 1 or coords.y == MAP_SIZE.y - 1


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


func _get_world_seed() -> int:
	var world_system := get_tree().root.get_node_or_null("WorldSystem")
	if world_system != null and world_system.has_method("get_seed"):
		return world_system.get_seed()
	return 0


func _set_world_seed(world_seed: int) -> void:
	var world_system := get_tree().root.get_node_or_null("WorldSystem")
	if world_system != null and world_system.has_method("set_seed"):
		world_system.set_seed(world_seed)
