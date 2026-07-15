class_name TerrainGenerator
extends Node


func generate_base(
	ground_layer: TileMapLayer,
	objects_layer: TileMapLayer,
	world_seed: int,
	noise_frequency: float,
	sparse_tree_density: float,
	playable_rect: Rect2i,
	spawn_coords: Vector2i,
	source_id: int,
	grass_tile: Vector2i,
	rock_tile: Vector2i,
	tree_tile: Vector2i
) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = noise_frequency
	for y in range(playable_rect.position.y, playable_rect.end.y):
		for x in range(playable_rect.position.x, playable_rect.end.x):
			var coords := Vector2i(x, y)
			ground_layer.set_cell(coords, source_id, grass_tile, 0)
			if _is_rect_edge(coords, playable_rect):
				objects_layer.set_cell(coords, source_id, rock_tile, 0)
				continue
			if _is_spawn_area(coords, spawn_coords):
				continue
			var noise_value := (noise.get_noise_2d(coords.x, coords.y) + 1.0) * 0.5
			if noise_value >= 0.78:
				objects_layer.set_cell(coords, source_id, tree_tile, 0)
			elif noise_value >= 0.62 and _passes_sparse_tree_roll(world_seed, coords, sparse_tree_density):
				objects_layer.set_cell(coords, source_id, tree_tile, 0)


func _is_rect_edge(coords: Vector2i, rect: Rect2i) -> bool:
	return coords.x == rect.position.x or coords.y == rect.position.y \
		or coords.x == rect.end.x - 1 or coords.y == rect.end.y - 1


func _is_spawn_area(coords: Vector2i, spawn_coords: Vector2i) -> bool:
	return abs(coords.x - spawn_coords.x) <= 2 and abs(coords.y - spawn_coords.y) <= 2


func _passes_sparse_tree_roll(world_seed: int, coords: Vector2i, density: float) -> bool:
	var roll := posmod(hash("%d:%d:%d" % [world_seed, coords.x, coords.y]), 10000) / 10000.0
	return roll < density
