class_name EnemyDirector
extends Node

const ACID_CRAWLER_SPAWNER_SCENE_PATH := "res://scenes/AcidCrawlerSpawner.tscn"
const ENEMY_SPAWNER_SCENE_PATH := "res://scenes/EnemySpawner.tscn"
const LIGHT_SWARMER_SCENE_PATH := "res://scenes/LightSwarmer.tscn"

var host: Node2D
var ground_layer: TileMapLayer
var generated_props: Node2D
var _scene_cache: Dictionary[String, PackedScene] = {}


func configure(owner: Node2D, ground: TileMapLayer, props: Node2D) -> void:
	host = owner
	ground_layer = ground
	generated_props = props


func place_acid_crawler_spawn(world_seed: int) -> void:
	if generated_props == null or host._river_tile_coords.is_empty():
		return
	var coords := _find_acid_spawn_tile(world_seed)
	if coords == Vector2i(-1, -1):
		return
	host.call("_clear_tree_patch", coords, 1, 1)
	_spawn_crawler(coords, "AcidCrawlerSpawner")


func _find_acid_spawn_tile(_world_seed: int) -> Vector2i:
	var sulfur_origin: Vector2i = host.MAP_SIZE - host.SULFUR_FLATS_SIZE
	var south_min: int = host.MAP_SIZE.y - 12
	var river_anchor := Vector2i(-1, -1)
	for coords: Vector2i in host._river_tile_coords:
		if coords.y >= south_min and coords.x > river_anchor.x:
			river_anchor = coords
	var min_x := maxi(river_anchor.x + 3, sulfur_origin.x - 12)
	var max_x: int = sulfur_origin.x - 2
	if min_x > max_x:
		min_x = sulfur_origin.x - 8
	var candidates: Array[Vector2i] = []
	for y in range(host.MAP_SIZE.y - 5, south_min - 1, -1):
		for x in range(min_x, max_x + 1):
			var coords := Vector2i(x, y)
			if _can_place(coords):
				candidates.append(coords)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(a.x - sulfur_origin.x) * 3.0 + a.y > float(b.x - sulfur_origin.x) * 3.0 + b.y
	)
	return candidates[0]


func _can_place(coords: Vector2i) -> bool:
	return not bool(host.call("_is_edge", coords)) and not bool(host.call("_is_spawn_area", coords)) \
		and not host._river_tile_coords.has(coords) \
		and not (host.call("_get_all_blocked_tiles") as Dictionary).has(coords) \
		and host.objects_layer.get_cell_source_id(coords) == -1


func place_sodium_shoals_threats() -> void:
	for coords: Vector2i in [host.SODIUM_SHOALS_ORIGIN + Vector2i(14, 4), host.SODIUM_SHOALS_ORIGIN + Vector2i(18, 14)]:
		if not bool(host.call("_is_edge", coords)):
			_spawn_crawler(coords, "ShoalsCrawlerSpawner_%d_%d" % [coords.x, coords.y])
	var golem_spawner := _get_scene(ENEMY_SPAWNER_SCENE_PATH).instantiate()
	golem_spawner.set("spawn_position", [
		ground_layer.to_global(ground_layer.map_to_local(host.SODIUM_SHOALS_ORIGIN + Vector2i(20, 3))),
		ground_layer.to_global(ground_layer.map_to_local(host.SODIUM_SHOALS_ORIGIN + Vector2i(21, 16))),
	])
	generated_props.add_child(golem_spawner)


func place_sulfur_flats_threats() -> void:
	for coords: Vector2i in [host.SULFUR_FLATS_ORIGIN + Vector2i(16, 4), host.SULFUR_FLATS_ORIGIN + Vector2i(20, 12)]:
		if not bool(host.call("_is_edge", coords)):
			_spawn_crawler(coords, "SulfurCrawlerSpawner_%d_%d" % [coords.x, coords.y])


func place_light_swarmer_spawners() -> void:
	var positions: Array[Vector2] = []
	for coords: Vector2i in [Vector2i(8, 50), Vector2i(56, 16)]:
		if bool(host.call("_is_edge", coords)):
			continue
		host.call("_clear_tree_patch", coords, 1, 1)
		positions.append(ground_layer.to_global(ground_layer.map_to_local(coords)))
	if positions.is_empty():
		return
	var spawner := _get_scene(ENEMY_SPAWNER_SCENE_PATH).instantiate()
	spawner.name = "LightSwarmerSpawner"
	spawner.set("enemy_scene", _get_scene(LIGHT_SWARMER_SCENE_PATH))
	spawner.set("spawn_position", positions)
	spawner.set("spawn_group_size", 3)
	spawner.set("spawn_group_radius", 16.0)
	spawner.set("requires_post_tutorial_loop", true)
	generated_props.add_child(spawner)


func _spawn_crawler(coords: Vector2i, node_name: String) -> void:
	var spawner := _get_scene(ACID_CRAWLER_SPAWNER_SCENE_PATH).instantiate()
	var position := ground_layer.to_global(ground_layer.map_to_local(coords))
	spawner.name = node_name
	spawner.position = position
	spawner.set("spawn_position", position)
	generated_props.add_child(spawner)


func _get_scene(scene_path: String) -> PackedScene:
	var scene := _scene_cache.get(scene_path) as PackedScene
	if scene == null:
		scene = load(scene_path) as PackedScene
		_scene_cache[scene_path] = scene
	return scene
