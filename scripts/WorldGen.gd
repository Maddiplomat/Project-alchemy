extends Node2D

enum WorldProfile { OVERWORLD, SODIUM_SHOALS, SULFUR_FLATS }

const MAP_SIZE := Vector2i(64, 64)
const TILE_SIZE := 16
const SOURCE_ID := 0
const GRASS_TILE := Vector2i(0, 0)
const TREE_TILE := Vector2i(1, 1)
const ROCK_TILE := Vector2i(2, 1)
const WATER_TILE := Vector2i(3, 0)
const SULFUR_FLATS_PLAY_RECT := Rect2i(3, 12, 40, 38)
const SULFUR_FLATS_ORIGIN := Vector2i(9, 18)
const SULFUR_FLATS_SIZE := Vector2i(28, 18)
const ELEMENT_SPAWN_SYSTEM_SCRIPT_PATH := "res://scripts/ElementSpawn.gd"
const CHARRED_SKELETON_PROP_SCENE_PATH := "res://scenes/CharredSkeletonProp.tscn"
const SODIUM_SHOALS_PLAY_RECT := Rect2i(2, 12, 38, 40)
const SODIUM_SHOALS_ORIGIN := Vector2i(11, 17)
const SODIUM_SHOALS_SIZE := Vector2i(26, 22)
const OVERWORLD_SCENE_PATH := "res://scenes/World.tscn"
const SODIUM_SHOALS_SCENE_PATH := "res://scenes/SodiumShoals.tscn"
const SULFUR_FLATS_SCENE_PATH := "res://scenes/SulfurFlats.tscn"
const SODIUM_SHOALS_DISCOVERY_ENTRY_ID := &"sodium_shoals_survey"
const SODIUM_SHOALS_DISCOVERY_TITLE := "Sodium Shoals Logged"
const SODIUM_SHOALS_DISCOVERY_NOTES := "The shoals hold sodium crusts around brine pans, with contaminated sediment warning signs near dumped industrial scrap."
const TREE_CANOPY_SOURCE_ID := SOURCE_ID
const TREE_CANOPY_ATLAS_COORDS := TREE_TILE
const IRON_MINE_COORDS := Vector2i(12, 8)
const OVERWORLD_SULFUR_TRAILHEAD_TILE := Vector2i(58, 54)
const TERRAIN_GENERATOR_SCRIPT_PATH := "res://scripts/TerrainGenerator.gd"
const PROP_SPAWNER_SCRIPT_PATH := "res://scripts/PropSpawner.gd"
const ENEMY_DIRECTOR_SCRIPT_PATH := "res://scripts/EnemyDirector.gd"
const TREE_MANAGER_SCRIPT_PATH := "res://scripts/TreeManager.gd"
const DEFAULT_CONFIG: WorldGenConfig = preload("res://data/config/world_gen_config.tres")

var _river_tile_coords: Array[Vector2i] = []
var _sulfur_flats_ash_tiles: Dictionary = {}
var _sulfur_flats_cracked_tiles: Dictionary = {}
var _sulfur_flats_lava_rock_tiles: Dictionary = {}
var _iron_hills_lithium_tiles: Dictionary = {}
var _iron_hills_lithium_deep_tiles: Dictionary = {}
var _sodium_shoals_tiles: Dictionary = {}
var _sodium_shoals_brine_tiles: Dictionary = {}
var _world_generation_id := 0
var _scene_cache: Dictionary[String, PackedScene] = {}
var _script_cache: Dictionary[String, Script] = {}
var terrain_generator: Node
var prop_spawner: Node
var enemy_director: Node
var tree_manager: Node

@export var generate_on_ready := true
@export var world_profile: WorldProfile = WorldProfile.OVERWORLD
@export var config: WorldGenConfig = DEFAULT_CONFIG

@onready var ground_layer: TileMapLayer = $Ground
@onready var decor_layer: TileMapLayer = $Decor
@onready var objects_layer: TileMapLayer = $Objects
@onready var element_spawn_system := get_node_or_null("ElementSpawnSystem") as Node2D
@onready var sulfur_flats_zone := get_node_or_null("SulfurFlatsZone") as Node2D
@onready var generated_zone_decor := _ensure_generated_child("GeneratedZoneDecor")
@onready var generated_zone_props := _ensure_generated_child("GeneratedZoneProps")
@onready var generated_tree_resources := _ensure_generated_child("GeneratedTreeResources")


func _ready() -> void:
	_ensure_active_game_session()
	_prepare_element_spawn_system()
	_setup_generation_components()
	if generate_on_ready:
		generate_world(_get_world_seed())
		var world_save_data := EventBus.get_world_save_data()
		if world_save_data != null and world_save_data.has_method("restore_pending_travel_state"):
			world_save_data.restore_pending_travel_state()
	_wire_camera_bounds()


func _ensure_active_game_session() -> void:
	if GameManager == null:
		return
	var world_system := EventBus.get_world_system()
	if world_system != null and world_system.has_method("has_pending_restore_state"):
		if bool(world_system.call("has_pending_restore_state")):
			return
	if GameManager.game_state == GameManager.GameState.BOOT \
		or GameManager.game_state == GameManager.GameState.MAIN_MENU:
		GameManager.start_new_game()


func generate_world(world_seed: int) -> void:
	if config == null:
		config = DEFAULT_CONFIG
	_world_generation_id += 1
	_set_world_seed(world_seed)
	_clear_layers()

	var playable_rect := _get_playable_rect()
	terrain_generator.generate_base(
		ground_layer, objects_layer, world_seed, config.noise_frequency, config.sparse_tree_density,
		playable_rect, _get_spawn_coords(), SOURCE_ID, GRASS_TILE, ROCK_TILE, TREE_TILE
	)
	tree_manager.begin_generation(_world_generation_id)

	match world_profile:
		WorldProfile.SODIUM_SHOALS:
			_generate_sodium_shoals(world_seed)
		WorldProfile.SULFUR_FLATS:
			_generate_sulfur_flats(world_seed)
		_:
			_generate_overworld(world_seed)


func regenerate_with_seed(world_seed: int) -> void:
	generate_world(world_seed)


func _clear_layers() -> void:
	ground_layer.clear()
	decor_layer.clear()
	objects_layer.clear()
	_river_tile_coords.clear()
	_sulfur_flats_ash_tiles.clear()
	_sulfur_flats_cracked_tiles.clear()
	_sulfur_flats_lava_rock_tiles.clear()
	_iron_hills_lithium_tiles.clear()
	_iron_hills_lithium_deep_tiles.clear()
	_sodium_shoals_tiles.clear()
	_sodium_shoals_brine_tiles.clear()
	_clear_generated_children(generated_zone_decor)
	_clear_generated_children(generated_zone_props)
	_clear_generated_children(generated_tree_resources)


func _generate_overworld(world_seed: int) -> void:
	_place_iron_hills_lithium_zone()
	_place_river_cluster(world_seed)
	prop_spawner.place_stone_quarry(world_seed)
	prop_spawner.place_iron_mine()
	prop_spawner.place_limestone_mine()
	prop_spawner.place_battery_station(world_seed)
	prop_spawner.place_overworld_sodium_trailhead()
	prop_spawner.place_overworld_sulfur_trailhead()
	tree_manager.spawn_interactive_trees(world_seed)
	_spawn_elements(world_seed)
	_spawn_lithium_deposits(world_seed)
	_spawn_water_pickups(world_seed)
	enemy_director.place_light_swarmer_spawners()


func _generate_sodium_shoals(world_seed: int) -> void:
	_log_sodium_shoals_discovery()
	_place_sodium_shoals_zone(world_seed)
	prop_spawner.place_sodium_return_trailhead()
	prop_spawner.place_sodium_contamination_props()
	_spawn_elements(world_seed)
	_spawn_sodium_deposits(world_seed)
	_spawn_mercury_deposits(world_seed)
	enemy_director.place_sodium_shoals_threats()


func _generate_sulfur_flats(world_seed: int) -> void:
	_place_sulfur_flats_zone()
	prop_spawner.place_sulfur_return_trailhead()
	_spawn_elements(world_seed)
	_spawn_sulfur_crystals(world_seed)
	enemy_director.place_sulfur_flats_threats()


func _place_river_cluster(world_seed: int) -> void:
	_river_tile_coords.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 3571

	# Anchor the river to the lower-left quadrant, away from spawn centre
	var anchor := Vector2i(
		rng.randi_range(8, MAP_SIZE.x / 4),
		rng.randi_range(MAP_SIZE.y / 2, MAP_SIZE.y - 10)
	)

	var current := anchor
	var river_length := rng.randi_range(12, 16)
	for _step in range(river_length):
		_paint_river_tile(current)

		if rng.randf() < 0.35:
			var bank_offset := Vector2i(0, 1 if rng.randf() < 0.5 else -1)
			_paint_river_tile(current + bank_offset)

		var vertical_shift := 0
		if rng.randf() < 0.55:
			vertical_shift = rng.randi_range(-1, 1)
		var next := current + Vector2i(1, vertical_shift)
		next.x = clampi(next.x, 1, MAP_SIZE.x - 2)
		next.y = clampi(next.y, 1, MAP_SIZE.y - 2)
		current = next


func _is_edge(coords: Vector2i) -> bool:
	return coords.x == 0 or coords.y == 0 or coords.x == MAP_SIZE.x - 1 or coords.y == MAP_SIZE.y - 1


func _get_playable_rect() -> Rect2i:
	match world_profile:
		WorldProfile.SODIUM_SHOALS:
			return SODIUM_SHOALS_PLAY_RECT
		WorldProfile.SULFUR_FLATS:
			return SULFUR_FLATS_PLAY_RECT
		_:
			return Rect2i(Vector2i.ZERO, MAP_SIZE)


func _is_spawn_area(coords: Vector2i) -> bool:
	var spawn_coords := _get_spawn_coords()
	return abs(coords.x - spawn_coords.x) <= 2 and abs(coords.y - spawn_coords.y) <= 2


func _get_spawn_coords() -> Vector2i:
	var spawn_coords := Vector2i(MAP_SIZE.x >> 1, MAP_SIZE.y >> 1)
	if world_profile == WorldProfile.SODIUM_SHOALS:
		spawn_coords = Vector2i(
			SODIUM_SHOALS_PLAY_RECT.position.x + 5,
			SODIUM_SHOALS_PLAY_RECT.position.y + (SODIUM_SHOALS_PLAY_RECT.size.y >> 1)
		)
	elif world_profile == WorldProfile.SULFUR_FLATS:
		spawn_coords = Vector2i(
			SULFUR_FLATS_PLAY_RECT.position.x + 5,
			SULFUR_FLATS_PLAY_RECT.position.y + (SULFUR_FLATS_PLAY_RECT.size.y >> 1)
		)
	return spawn_coords


func _prepare_element_spawn_system() -> void:
	if element_spawn_system == null:
		return

	if element_spawn_system.get_script() == null:
		element_spawn_system.set_script(_get_script(ELEMENT_SPAWN_SYSTEM_SCRIPT_PATH))


func _spawn_elements(world_seed: int) -> void:
	_prepare_element_spawn_system()
	if element_spawn_system != null and element_spawn_system.has_method("spawn_elements"):
		element_spawn_system.spawn_elements(
			ground_layer,
			objects_layer,
			world_seed,
			_get_all_spawn_blocked_tiles()
		)


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
		var tmp: Vector2i = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	for i in range(mini(count, shuffled.size())):
		_spawn_water_pickup_at(shuffled[i], _world_generation_id)


func _spawn_water_pickups_fallback(world_seed: int) -> void:
	if element_spawn_system == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 4201
	var count := rng.randi_range(4, 6)
	var shuffled := _river_tile_coords.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2i = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	for i in range(mini(count, shuffled.size())):
		_spawn_water_pickup_at(shuffled[i], _world_generation_id)


func _paint_river_tile(coords: Vector2i) -> void:
	if _is_edge(coords):
		return
	ground_layer.set_cell(coords, SOURCE_ID, WATER_TILE, 0)
	objects_layer.erase_cell(coords)
	if not _river_tile_coords.has(coords):
		_river_tile_coords.append(coords)


func _place_sulfur_flats_zone() -> void:
	var zone_origin := SULFUR_FLATS_ORIGIN
	var zone_rect := Rect2i(zone_origin, SULFUR_FLATS_SIZE)
	var boundary_y := zone_origin.y + (SULFUR_FLATS_SIZE.y / 2)

	for y in range(zone_rect.position.y, zone_rect.end.y):
		for x in range(zone_rect.position.x, zone_rect.end.x):
			var coords := Vector2i(x, y)
			var local_coords := coords - zone_rect.position
			if not _is_sulfur_flats_zone_tile(local_coords):
				continue
			objects_layer.erase_cell(coords)

			if _is_sulfur_flats_path_tile(local_coords):
				_sulfur_flats_ash_tiles[coords] = true
				_draw_sulfur_tile(coords, true)
				continue
			if _is_sulfur_lava_rock_tile(zone_rect, coords):
				objects_layer.set_cell(coords, SOURCE_ID, ROCK_TILE, 0)
				_sulfur_flats_lava_rock_tiles[coords] = true
			elif _is_sulfur_cracked_tile(zone_rect, coords):
				_sulfur_flats_cracked_tiles[coords] = true
			else:
				_sulfur_flats_ash_tiles[coords] = true

			_draw_sulfur_tile(coords)

	var skeleton_tile := zone_origin + Vector2i(5, (SULFUR_FLATS_SIZE.y / 2) + 2)
	_clear_tree_patch(skeleton_tile, 1, 1)

	var charred_skeleton := _get_scene(CHARRED_SKELETON_PROP_SCENE_PATH).instantiate()
	generated_zone_props.add_child(charred_skeleton)
	charred_skeleton.position = ground_layer.map_to_local(skeleton_tile) + Vector2(-2.0, 4.0)

	if sulfur_flats_zone != null and sulfur_flats_zone.has_method("configure_zone"):
		sulfur_flats_zone.configure_zone(ground_layer, _get_sulfur_flats_ash_tile_array())


func _is_sulfur_flats_zone_tile(local_coords: Vector2i) -> bool:
	if local_coords.x < 0 or local_coords.y < 0:
		return false
	if local_coords.x >= SULFUR_FLATS_SIZE.x or local_coords.y >= SULFUR_FLATS_SIZE.y:
		return false
	var center := Vector2(float(SULFUR_FLATS_SIZE.x) * 0.58, float(SULFUR_FLATS_SIZE.y) * 0.50)
	var normalized := Vector2(
		(float(local_coords.x) - center.x) / (float(SULFUR_FLATS_SIZE.x) * 0.46),
		(float(local_coords.y) - center.y) / (float(SULFUR_FLATS_SIZE.y) * 0.48)
	)
	if normalized.length() > 1.0:
		return false
	var mid_y := SULFUR_FLATS_SIZE.y / 2
	if local_coords.x <= 2 and abs(local_coords.y - mid_y) > 1:
		return false
	if local_coords.x <= 5 and abs(local_coords.y - mid_y) > 3:
		return false
	if local_coords.y <= 1 and local_coords.x <= 6:
		return false
	if local_coords.y >= SULFUR_FLATS_SIZE.y - 2 and local_coords.x >= SULFUR_FLATS_SIZE.x - 5:
		return false
	return true


func _is_sulfur_flats_path_tile(local_coords: Vector2i) -> bool:
	var mid_y := SULFUR_FLATS_SIZE.y / 2
	return local_coords.x <= 5 and abs(local_coords.y - mid_y) <= 1


func _place_iron_hills_lithium_zone() -> void:
	var zone_origin := Vector2i(MAP_SIZE.x - config.iron_hills_lithium_size.x, 0)
	var zone_rect := Rect2i(zone_origin, config.iron_hills_lithium_size)

	for y in range(zone_rect.position.y, zone_rect.end.y):
		for x in range(zone_rect.position.x, zone_rect.end.x):
			var coords := Vector2i(x, y)
			if not _is_iron_hills_lithium_zone_tile(zone_rect, coords):
				continue
			objects_layer.erase_cell(coords)
			_iron_hills_lithium_tiles[coords] = true
			if _is_iron_hills_lithium_deep_tile(zone_rect, coords):
				_iron_hills_lithium_deep_tiles[coords] = true

	for coords: Vector2i in _iron_hills_lithium_tiles.keys():
		_draw_iron_hills_lithium_tile(coords)

	_place_iron_hills_lithium_teaching_props(zone_origin)


func _is_iron_hills_lithium_zone_tile(zone_rect: Rect2i, coords: Vector2i) -> bool:
	var local_coords := coords - zone_rect.position
	if local_coords.x < 0 or local_coords.y < 0:
		return false
	if local_coords.x >= config.iron_hills_lithium_size.x or local_coords.y >= config.iron_hills_lithium_size.y:
		return false

	# Shape an inset quarry pocket so the lithium area reads as an Iron Hills sub-zone, not a map-edge stamp.
	if local_coords.x <= 0 or local_coords.y <= 0:
		return false
	if local_coords.x >= config.iron_hills_lithium_size.x - 1 or local_coords.y >= config.iron_hills_lithium_size.y - 1:
		return false
	if local_coords.x == 1 and local_coords.y <= 2:
		return false
	if local_coords.x <= 2 and local_coords.y == 1:
		return false
	if local_coords.x >= config.iron_hills_lithium_size.x - 3 and local_coords.y == 1:
		return false
	if local_coords.x == config.iron_hills_lithium_size.x - 2 and local_coords.y == 2:
		return false
	if local_coords.y >= config.iron_hills_lithium_size.y - 2 and local_coords.x == 1:
		return false
	return true


func _is_iron_hills_lithium_deep_tile(zone_rect: Rect2i, coords: Vector2i) -> bool:
	var local_coords := coords - zone_rect.position
	if not _is_iron_hills_lithium_zone_tile(zone_rect, coords):
		return false
	if local_coords.x <= 2 or local_coords.y <= 2:
		return false
	if local_coords.x >= config.iron_hills_lithium_size.x - 2 or local_coords.y >= config.iron_hills_lithium_size.y - 2:
		return false
	return local_coords.x >= 4 and local_coords.y >= 3


func _draw_iron_hills_lithium_tile(coords: Vector2i) -> void:
	var tile_root_name := "IronHillsLithiumTile_%d_%d" % [coords.x, coords.y]
	var existing_tile := generated_zone_decor.get_node_or_null(tile_root_name)
	if existing_tile != null:
		existing_tile.queue_free()

	var tile_root := Node2D.new()
	tile_root.name = tile_root_name
	tile_root.position = ground_layer.map_to_local(coords)
	generated_zone_decor.add_child(tile_root)

	var local_coords := _get_iron_hills_lithium_local_coords(coords)
	var silhouette := _build_iron_hills_lithium_tile_polygon(coords)
	var base := Polygon2D.new()
	base.polygon = silhouette
	base.color = _get_iron_hills_lithium_base_color(coords)
	base.z_index = 0
	tile_root.add_child(base)

	var iron_shadow := Polygon2D.new()
	iron_shadow.polygon = PackedVector2Array([
		Vector2(-7.0, -6.0),
		Vector2(4.0, -7.0),
		Vector2(6.0, 2.0),
		Vector2(-5.0, 6.0),
	])
	iron_shadow.color = Color(0.29, 0.34, 0.40, 0.26 if _iron_hills_lithium_deep_tiles.has(coords) else 0.18)
	iron_shadow.z_index = 0
	tile_root.add_child(iron_shadow)

	if _iron_hills_lithium_deep_tiles.has(coords):
		var deep_glow := Polygon2D.new()
		deep_glow.polygon = PackedVector2Array([
			Vector2(-5.0, -4.0),
			Vector2(5.0, -5.0),
			Vector2(5.0, 4.0),
			Vector2(-4.0, 5.0),
		])
		deep_glow.color = Color(0.44, 0.72, 0.98, 0.28)
		deep_glow.z_index = 1
		tile_root.add_child(deep_glow)

	var ridge_highlight := Polygon2D.new()
	ridge_highlight.polygon = PackedVector2Array([
		Vector2(-7.0, -7.0),
		Vector2(0.0, -8.0),
		Vector2(-1.0, -2.0),
		Vector2(-8.0, -1.0),
	])
	ridge_highlight.color = Color(0.86, 0.93, 0.99, 0.26)
	ridge_highlight.z_index = 1
	tile_root.add_child(ridge_highlight)

	_add_iron_hills_lithium_contour_edges(tile_root, coords)

	if (local_coords.x * 3 + local_coords.y * 7) % 5 == 0:
		var vein := Line2D.new()
		vein.default_color = Color(0.42, 0.71, 0.97, 0.78)
		vein.width = 1.0
		vein.z_index = 2
		vein.points = PackedVector2Array([
			Vector2(-6.0, 4.0),
			Vector2(-2.0, 1.0),
			Vector2(1.0, -2.0),
			Vector2(5.0, -5.0),
		])
		tile_root.add_child(vein)
	elif (local_coords.x * 11 + local_coords.y * 13) % 7 == 0:
		var outcrop := Polygon2D.new()
		outcrop.polygon = PackedVector2Array([
			Vector2(-4.0, -1.0),
			Vector2(-1.0, -5.0),
			Vector2(3.0, -1.0),
			Vector2(1.0, 4.0),
			Vector2(-3.0, 3.0),
		])
		outcrop.color = Color(0.56, 0.76, 0.95, 0.46)
		outcrop.z_index = 2
		tile_root.add_child(outcrop)
	elif _iron_hills_lithium_deep_tiles.has(coords):
		var shimmer := Line2D.new()
		shimmer.default_color = Color(0.58, 0.88, 1.0, 0.58)
		shimmer.width = 0.8
		shimmer.z_index = 3
		shimmer.points = PackedVector2Array([
			Vector2(-2.0, 3.0),
			Vector2(0.0, 0.5),
			Vector2(3.0, -3.0),
		])
		tile_root.add_child(shimmer)


func _place_iron_hills_lithium_teaching_props(zone_origin: Vector2i) -> void:
	var puddle_tile := zone_origin + Vector2i(1, config.iron_hills_lithium_size.y - 2)
	var charred_tile := puddle_tile + Vector2i(1, -1)
	_clear_tree_patch(puddle_tile, 1, 1)
	_clear_tree_patch(charred_tile, 1, 1)

	var puddle := _build_rain_warning_puddle()
	generated_zone_props.add_child(puddle)
	puddle.position = ground_layer.map_to_local(puddle_tile) + Vector2(0.0, 3.0)

	var charred_deposit := _build_charred_lithium_deposit_prop()
	generated_zone_props.add_child(charred_deposit)
	charred_deposit.position = ground_layer.map_to_local(charred_tile) + Vector2(0.0, 1.0)


func _place_sodium_shoals_zone(world_seed: int) -> void:
	var zone_rect := Rect2i(SODIUM_SHOALS_ORIGIN, SODIUM_SHOALS_SIZE)
	for y in range(zone_rect.position.y, zone_rect.end.y):
		for x in range(zone_rect.position.x, zone_rect.end.x):
			var coords := Vector2i(x, y)
			if _is_edge(coords):
				continue
			var local_coords := coords - zone_rect.position
			if not _is_sodium_shoals_zone_tile(local_coords):
				continue
			objects_layer.erase_cell(coords)
			if _is_sodium_shoals_brine_tile(local_coords, world_seed):
				_paint_river_tile(coords)
				_sodium_shoals_brine_tiles[coords] = true
				_draw_sodium_brine_tile(coords, local_coords)
				continue
			_sodium_shoals_tiles[coords] = true
			_draw_sodium_shoal_tile(coords, local_coords)


func _is_sodium_shoals_zone_tile(local_coords: Vector2i) -> bool:
	if local_coords.x < 0 or local_coords.y < 0:
		return false
	if local_coords.x >= SODIUM_SHOALS_SIZE.x or local_coords.y >= SODIUM_SHOALS_SIZE.y:
		return false
	var center := Vector2((SODIUM_SHOALS_SIZE.x - 1) * 0.5, (SODIUM_SHOALS_SIZE.y - 1) * 0.5)
	var normalized := Vector2(
		(float(local_coords.x) - center.x) / (float(SODIUM_SHOALS_SIZE.x) * 0.46),
		(float(local_coords.y) - center.y) / (float(SODIUM_SHOALS_SIZE.y) * 0.48)
	)
	var distance := normalized.length()
	if distance > 1.0:
		return false
	if local_coords.x <= 2 and abs(local_coords.y - int(center.y)) > 2:
		return false
	if local_coords.x >= SODIUM_SHOALS_SIZE.x - 3 and local_coords.y <= 4:
		return false
	if local_coords.y <= 2 and local_coords.x <= 4:
		return false
	if local_coords.y >= SODIUM_SHOALS_SIZE.y - 2 and local_coords.x >= SODIUM_SHOALS_SIZE.x - 5:
		return false
	return true


func _is_sodium_shoals_brine_tile(local_coords: Vector2i, world_seed: int) -> bool:
	var brine_roll: float = posmod(hash("%d:%d:%d" % [world_seed, local_coords.x, local_coords.y]), 1000) / 1000.0
	var center_basin: bool = _is_point_in_ellipse(local_coords, Vector2(14.0, 10.0), Vector2(5.8, 4.4))
	var south_basin: bool = _is_point_in_ellipse(local_coords, Vector2(11.0, 16.5), Vector2(7.0, 3.0))
	var east_basin: bool = _is_point_in_ellipse(local_coords, Vector2(20.0, 11.5), Vector2(3.6, 5.0))
	var west_inlet: bool = local_coords.x >= 2 and local_coords.x <= 8 and abs(local_coords.y - 11) <= 1
	var basin_edge_noise: bool = brine_roll < 0.12 and (
		_is_point_in_ellipse(local_coords, Vector2(14.0, 10.0), Vector2(6.7, 5.3))
		or _is_point_in_ellipse(local_coords, Vector2(11.0, 16.5), Vector2(7.8, 3.8))
	)
	return center_basin or south_basin or east_basin or west_inlet or basin_edge_noise


func _draw_sodium_shoal_tile(coords: Vector2i, local_coords: Vector2i) -> void:
	var tile_root_name := "SodiumShoalTile_%d_%d" % [coords.x, coords.y]
	var existing_tile := generated_zone_decor.get_node_or_null(tile_root_name)
	if existing_tile != null:
		existing_tile.queue_free()

	var tile_root := Node2D.new()
	tile_root.name = tile_root_name
	tile_root.position = ground_layer.map_to_local(coords)
	generated_zone_decor.add_child(tile_root)

	var shade_roll := posmod(local_coords.x * 19 + local_coords.y * 31, 100) / 100.0
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-8.0, -8.0),
		Vector2(8.0, -8.0),
		Vector2(8.0, 8.0),
		Vector2(-8.0, 8.0),
	])
	base.color = Color(
		0.78 + shade_roll * 0.06,
		0.79 + shade_roll * 0.05,
		0.74 + shade_roll * 0.04,
		1.0
	)
	tile_root.add_child(base)

	if (local_coords.x + local_coords.y) % 3 == 0:
		var crust := Line2D.new()
		crust.default_color = Color(0.95, 0.96, 0.90, 0.78)
		crust.width = 1.0
		crust.points = PackedVector2Array([
			Vector2(-6.0, 3.0),
			Vector2(-1.0, -1.0),
			Vector2(5.0, -4.0),
		])
		tile_root.add_child(crust)
	if posmod(local_coords.x * 11 + local_coords.y * 7, 17) <= 2:
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([
			Vector2(-2.0, -5.0),
			Vector2(2.0, -4.0),
			Vector2(4.0, 1.0),
			Vector2(0.0, 4.0),
			Vector2(-4.0, 0.0),
		])
		shard.color = Color(0.88, 0.90, 0.94, 0.42)
		shard.z_index = 1
		tile_root.add_child(shard)


func _draw_sodium_brine_tile(coords: Vector2i, local_coords: Vector2i) -> void:
	var tile_root_name := "SodiumBrineTile_%d_%d" % [coords.x, coords.y]
	var existing_tile := generated_zone_decor.get_node_or_null(tile_root_name)
	if existing_tile != null:
		existing_tile.queue_free()

	var tile_root := Node2D.new()
	tile_root.name = tile_root_name
	tile_root.position = ground_layer.map_to_local(coords)
	generated_zone_decor.add_child(tile_root)

	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-7.0, -6.0),
		Vector2(6.0, -7.0),
		Vector2(7.0, 5.0),
		Vector2(-6.0, 7.0),
	])
	var tint_roll := posmod(local_coords.x * 23 + local_coords.y * 13, 100) / 100.0
	base.color = Color(
		0.54 + tint_roll * 0.06,
		0.64 + tint_roll * 0.05,
		0.66 + tint_roll * 0.04,
		0.92
	)
	base.z_index = 1
	tile_root.add_child(base)

	var rim := Line2D.new()
	rim.default_color = Color(0.92, 0.94, 0.88, 0.82)
	rim.width = 1.0
	rim.z_index = 2
	rim.points = PackedVector2Array([
		Vector2(-5.0, 3.0),
		Vector2(-2.0, -2.0),
		Vector2(2.0, -3.5),
		Vector2(5.0, -1.0),
	])
	tile_root.add_child(rim)

	if posmod(local_coords.x * 5 + local_coords.y * 9, 6) == 0:
		var sheen := Line2D.new()
		sheen.default_color = Color(0.80, 0.90, 0.93, 0.44)
		sheen.width = 0.8
		sheen.z_index = 3
		sheen.points = PackedVector2Array([
			Vector2(-3.0, 1.0),
			Vector2(0.0, -1.0),
			Vector2(3.0, -2.0),
		])
		tile_root.add_child(sheen)


func _spawn_sodium_deposits(world_seed: int) -> void:
	if element_spawn_system == null or not element_spawn_system.has_method("spawn_element_at"):
		return
	var candidate_tiles := _get_sodium_shoals_spawn_tiles()
	if candidate_tiles.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 45107
	for index in range(candidate_tiles.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidate_tiles[index]
		candidate_tiles[index] = candidate_tiles[swap_index]
		candidate_tiles[swap_index] = tmp
	var spawn_count := mini(rng.randi_range(config.sodium_spawn_min, config.sodium_spawn_max), candidate_tiles.size())
	for index in range(spawn_count):
		element_spawn_system.spawn_element_at(&"sodium", candidate_tiles[index], ground_layer)


func _spawn_mercury_deposits(world_seed: int) -> void:
	if element_spawn_system == null or not element_spawn_system.has_method("spawn_element_at"):
		return
	var candidate_tiles := _get_mercury_shoals_spawn_tiles()
	if candidate_tiles.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 60257
	for index in range(candidate_tiles.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidate_tiles[index]
		candidate_tiles[index] = candidate_tiles[swap_index]
		candidate_tiles[swap_index] = tmp
	var spawn_count := mini(rng.randi_range(config.mercury_spawn_min, config.mercury_spawn_max), candidate_tiles.size())
	for index in range(spawn_count):
		element_spawn_system.spawn_element_at(&"mercury", candidate_tiles[index], ground_layer)


func _get_sodium_shoals_spawn_tiles() -> Array[Vector2i]:
	var spawn_tiles: Array[Vector2i] = []
	for coords: Vector2i in _sodium_shoals_tiles.keys():
		if coords.x <= SODIUM_SHOALS_ORIGIN.x + 3:
			continue
		if coords.y >= SODIUM_SHOALS_ORIGIN.y + SODIUM_SHOALS_SIZE.y - 2:
			continue
		spawn_tiles.append(coords)
	return spawn_tiles


func _get_mercury_shoals_spawn_tiles() -> Array[Vector2i]:
	var spawn_tiles: Array[Vector2i] = []
	for coords: Vector2i in _sodium_shoals_tiles.keys():
		var local_coords := coords - SODIUM_SHOALS_ORIGIN
		if local_coords.x < 11:
			continue
		if local_coords.y < 7:
			continue
		if not _has_adjacent_sodium_shoals_brine_tile(coords):
			continue
		spawn_tiles.append(coords)
	return spawn_tiles


func _has_adjacent_sodium_shoals_brine_tile(coords: Vector2i) -> bool:
	var neighbor_offsets := [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	for offset: Vector2i in neighbor_offsets:
		if _sodium_shoals_brine_tiles.has(coords + offset):
			return true
	return false


func _log_sodium_shoals_discovery() -> void:
	if EventBus.get_discovery_log() == null or not EventBus.get_discovery_log().has_method("log_progression_discovery"):
		return
	EventBus.get_discovery_log().log_progression_discovery(
		SODIUM_SHOALS_DISCOVERY_ENTRY_ID,
		SODIUM_SHOALS_DISCOVERY_TITLE,
		SODIUM_SHOALS_DISCOVERY_NOTES
	)


func _is_point_in_ellipse(local_coords: Vector2i, center: Vector2, radii: Vector2) -> bool:
	if radii.x <= 0.0 or radii.y <= 0.0:
		return false
	var normalized := Vector2(
		(float(local_coords.x) - center.x) / radii.x,
		(float(local_coords.y) - center.y) / radii.y
	)
	return normalized.length_squared() <= 1.0


func _get_iron_hills_lithium_local_coords(coords: Vector2i) -> Vector2i:
	var zone_origin := Vector2i(MAP_SIZE.x - config.iron_hills_lithium_size.x, 0)
	return coords - zone_origin


func _build_iron_hills_lithium_tile_polygon(coords: Vector2i) -> PackedVector2Array:
	var has_north := _iron_hills_lithium_tiles.has(coords + Vector2i(0, -1))
	var has_south := _iron_hills_lithium_tiles.has(coords + Vector2i(0, 1))
	var has_west := _iron_hills_lithium_tiles.has(coords + Vector2i(-1, 0))
	var has_east := _iron_hills_lithium_tiles.has(coords + Vector2i(1, 0))

	var north_inset := -8.0 if has_north else -6.5
	var south_inset := 8.0 if has_south else 6.0
	var west_inset := -8.0 if has_west else -6.0
	var east_inset := 8.0 if has_east else 6.5
	return PackedVector2Array([
		Vector2(west_inset, north_inset + 1.0),
		Vector2(-1.5, north_inset),
		Vector2(east_inset - 1.0, north_inset + 0.5),
		Vector2(east_inset, 1.0),
		Vector2(east_inset - 0.5, south_inset),
		Vector2(-2.0, south_inset - 0.5),
		Vector2(west_inset + 0.5, south_inset - 1.0),
		Vector2(west_inset, -1.0),
	])


func _get_iron_hills_lithium_base_color(coords: Vector2i) -> Color:
	var local_coords := _get_iron_hills_lithium_local_coords(coords)
	var shade_roll := posmod(local_coords.x * 17 + local_coords.y * 29, 100) / 100.0
	if _iron_hills_lithium_deep_tiles.has(coords):
		return Color(
			0.41 + shade_roll * 0.05,
			0.53 + shade_roll * 0.05,
			0.64 + shade_roll * 0.04,
			1.0
		)
	return Color(
		0.47 + shade_roll * 0.05,
		0.55 + shade_roll * 0.05,
		0.63 + shade_roll * 0.04,
		1.0
	)


func _add_iron_hills_lithium_contour_edges(tile_root: Node2D, coords: Vector2i) -> void:
	var edge_color := Color(0.20, 0.24, 0.29, 0.72)
	var glow_color := Color(0.54, 0.86, 1.0, 0.34)
	if not _iron_hills_lithium_tiles.has(coords + Vector2i(0, -1)):
		var north_ridge := Line2D.new()
		north_ridge.default_color = glow_color
		north_ridge.width = 1.0
		north_ridge.z_index = 2
		north_ridge.points = PackedVector2Array([
			Vector2(-5.0, -5.5),
			Vector2(-1.0, -7.0),
			Vector2(5.0, -6.0),
		])
		tile_root.add_child(north_ridge)
	if not _iron_hills_lithium_tiles.has(coords + Vector2i(-1, 0)):
		var west_edge := Line2D.new()
		west_edge.default_color = edge_color
		west_edge.width = 1.1
		west_edge.z_index = 2
		west_edge.points = PackedVector2Array([
			Vector2(-6.0, -4.0),
			Vector2(-7.0, 0.0),
			Vector2(-5.5, 5.0),
		])
		tile_root.add_child(west_edge)
	if not _iron_hills_lithium_tiles.has(coords + Vector2i(1, 0)):
		var east_edge := Line2D.new()
		east_edge.default_color = edge_color
		east_edge.width = 1.1
		east_edge.z_index = 2
		east_edge.points = PackedVector2Array([
			Vector2(5.5, -5.0),
			Vector2(7.0, -1.0),
			Vector2(6.0, 4.0),
		])
		tile_root.add_child(east_edge)
	if not _iron_hills_lithium_tiles.has(coords + Vector2i(0, 1)):
		var south_edge := Line2D.new()
		south_edge.default_color = Color(0.18, 0.22, 0.27, 0.76)
		south_edge.width = 1.2
		south_edge.z_index = 2
		south_edge.points = PackedVector2Array([
			Vector2(-4.0, 5.0),
			Vector2(1.0, 6.5),
			Vector2(6.0, 5.5),
		])
		tile_root.add_child(south_edge)


func _build_rain_warning_puddle() -> Node2D:
	var root := Node2D.new()
	root.name = "RainWarningPuddle"
	root.z_index = 4

	var puddle := Polygon2D.new()
	puddle.polygon = PackedVector2Array([
		Vector2(-10.0, 1.0),
		Vector2(-6.0, -5.0),
		Vector2(2.0, -7.0),
		Vector2(9.0, -2.0),
		Vector2(8.0, 5.0),
		Vector2(0.0, 7.0),
		Vector2(-8.0, 5.0),
	])
	puddle.color = Color(0.38, 0.52, 0.62, 0.84)
	root.add_child(puddle)

	var sheen := Line2D.new()
	sheen.default_color = Color(0.72, 0.84, 0.94, 0.55)
	sheen.width = 1.0
	sheen.points = PackedVector2Array([
		Vector2(-5.0, 0.0),
		Vector2(-1.0, -2.0),
		Vector2(4.0, -1.0),
	])
	root.add_child(sheen)
	return root


func _build_charred_lithium_deposit_prop() -> Node2D:
	var root := Node2D.new()
	root.name = "CharredLithiumDeposit"
	root.z_index = 5

	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-8.0, 5.0),
		Vector2(-6.0, -4.0),
		Vector2(-1.0, -7.0),
		Vector2(5.0, -5.0),
		Vector2(8.0, 2.0),
		Vector2(3.0, 8.0),
		Vector2(-4.0, 7.0),
	])
	body.color = Color(0.16, 0.17, 0.19, 1.0)
	root.add_child(body)

	var scorch := Polygon2D.new()
	scorch.polygon = PackedVector2Array([
		Vector2(-6.0, 3.0),
		Vector2(-3.0, -3.0),
		Vector2(1.0, -5.0),
		Vector2(5.0, 0.0),
		Vector2(1.0, 5.0),
		Vector2(-4.0, 5.0),
	])
	scorch.color = Color(0.09, 0.10, 0.11, 1.0)
	root.add_child(scorch)

	var lithium_crack := Line2D.new()
	lithium_crack.default_color = Color(0.54, 0.86, 1.0, 0.8)
	lithium_crack.width = 1.2
	lithium_crack.points = PackedVector2Array([
		Vector2(-3.0, 2.0),
		Vector2(-1.0, -1.0),
		Vector2(2.0, -4.0),
		Vector2(4.0, -2.0),
	])
	root.add_child(lithium_crack)
	return root


func _is_sulfur_cracked_tile(zone_rect: Rect2i, coords: Vector2i) -> bool:
	var local_coords := coords - zone_rect.position
	if _is_sulfur_flats_path_tile(local_coords):
		return false
	if local_coords.x >= SULFUR_FLATS_SIZE.x - 3 or local_coords.y >= SULFUR_FLATS_SIZE.y - 3:
		return false
	var basin := _is_point_in_ellipse(
		local_coords,
		Vector2(float(SULFUR_FLATS_SIZE.x) * 0.54, float(SULFUR_FLATS_SIZE.y) * 0.45),
		Vector2(5.4, 4.2)
	)
	return basin or posmod(local_coords.x * 5 + local_coords.y * 3, 11) <= 2


func _is_sulfur_lava_rock_tile(zone_rect: Rect2i, coords: Vector2i) -> bool:
	var local_coords := coords - zone_rect.position
	if _is_sulfur_flats_path_tile(local_coords):
		return false
	var east_ridge := local_coords.x >= SULFUR_FLATS_SIZE.x - 4 and local_coords.y >= 2
	var south_rim := local_coords.y >= SULFUR_FLATS_SIZE.y - 3 and local_coords.x >= (SULFUR_FLATS_SIZE.x / 3)
	var burn_core := _is_point_in_ellipse(
		local_coords,
		Vector2(float(SULFUR_FLATS_SIZE.x) * 0.74, float(SULFUR_FLATS_SIZE.y) * 0.63),
		Vector2(4.5, 3.0)
	)
	var northern_spur := local_coords.x >= 11 and local_coords.x <= 15 and local_coords.y <= 3
	return east_ridge or south_rim or burn_core or northern_spur


func _draw_sulfur_tile(coords: Vector2i, is_path: bool = false) -> void:
	var tile_root_name := "SulfurTile_%d_%d" % [coords.x, coords.y]
	var existing_tile := generated_zone_decor.get_node_or_null(tile_root_name)
	if existing_tile != null:
		existing_tile.queue_free()

	var tile_root := Node2D.new()
	tile_root.name = tile_root_name
	tile_root.position = ground_layer.map_to_local(coords)
	generated_zone_decor.add_child(tile_root)

	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-8.0, -8.0),
		Vector2(8.0, -8.0),
		Vector2(8.0, 8.0),
		Vector2(-8.0, 8.0),
	])
	base.color = _get_sulfur_tile_color(coords, is_path)
	base.z_index = 0
	tile_root.add_child(base)

	if _sulfur_flats_cracked_tiles.has(coords):
		var cracks := Line2D.new()
		cracks.default_color = Color(0.22, 0.20, 0.18, 0.9)
		cracks.width = 1.1
		cracks.z_index = 0
		cracks.points = PackedVector2Array([
			Vector2(-6.0, 4.0),
			Vector2(-1.0, 0.0),
			Vector2(1.0, -3.0),
			Vector2(6.0, -6.0),
		])
		tile_root.add_child(cracks)

		var crack_branch := Line2D.new()
		crack_branch.default_color = Color(0.18, 0.16, 0.14, 0.8)
		crack_branch.width = 0.9
		crack_branch.z_index = 0
		crack_branch.points = PackedVector2Array([
			Vector2(-2.0, 2.0),
			Vector2(0.0, 4.0),
			Vector2(3.0, 6.0),
		])
		tile_root.add_child(crack_branch)

	if _sulfur_flats_lava_rock_tiles.has(coords):
		var glow := Polygon2D.new()
		glow.polygon = PackedVector2Array([
			Vector2(-5.0, -4.0),
			Vector2(5.0, -5.0),
			Vector2(4.0, 4.0),
			Vector2(-4.0, 5.0),
		])
		glow.color = Color(0.83, 0.35, 0.12, 0.18)
		glow.z_index = 0
		tile_root.add_child(glow)


func _get_sulfur_tile_color(coords: Vector2i, is_path: bool) -> Color:
	if is_path:
		return Color(0.58, 0.57, 0.52, 1.0)
	if _sulfur_flats_lava_rock_tiles.has(coords):
		return Color(0.19, 0.20, 0.22, 1.0)
	if _sulfur_flats_cracked_tiles.has(coords):
		return Color(0.42, 0.40, 0.37, 1.0)
	return Color(0.55, 0.54, 0.49, 1.0)


func _clear_tree_patch(center_coords: Vector2i, half_width: int, half_height: int) -> void:
	for y in range(center_coords.y - half_height, center_coords.y + half_height + 1):
		for x in range(center_coords.x - half_width, center_coords.x + half_width + 1):
			var coords := Vector2i(x, y)
			if _is_edge(coords):
				continue
			objects_layer.erase_cell(coords)


func _spawn_water_pickup_at(coords: Vector2i, generation_id: int) -> void:
	if element_spawn_system == null:
		return
	if element_spawn_system.has_method("get_pickup_at_tile"):
		var existing_pickup = element_spawn_system.get_pickup_at_tile(coords)
		if existing_pickup != null:
			return
	if not element_spawn_system.has_method("spawn_element_at"):
		return
	var pickup: Node2D = element_spawn_system.spawn_element_at(&"water", coords, ground_layer)
	if pickup == null:
		return
	if pickup.has_signal("picked_up"):
		var callback := Callable(self, "_on_water_pickup_collected").bind(coords, generation_id)
		if not pickup.is_connected("picked_up", callback):
			pickup.connect("picked_up", callback, CONNECT_ONE_SHOT)


func _spawn_sulfur_crystals(world_seed: int) -> void:
	if element_spawn_system == null or not element_spawn_system.has_method("spawn_element_at"):
		return
	var candidate_tiles := _get_sulfur_flats_spawn_tiles()
	if candidate_tiles.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 8429
	for index in range(candidate_tiles.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidate_tiles[index]
		candidate_tiles[index] = candidate_tiles[swap_index]
		candidate_tiles[swap_index] = tmp

	var spawn_count := mini(rng.randi_range(config.sulfur_spawn_min, config.sulfur_spawn_max), candidate_tiles.size())
	for index in range(spawn_count):
		element_spawn_system.spawn_element_at(&"sulfur", candidate_tiles[index], ground_layer)


func _spawn_lithium_deposits(world_seed: int) -> void:
	if element_spawn_system == null or not element_spawn_system.has_method("spawn_element_at"):
		return
	var candidate_tiles := _get_iron_hills_lithium_spawn_tiles()
	if candidate_tiles.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 12553
	for index in range(candidate_tiles.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidate_tiles[index]
		candidate_tiles[index] = candidate_tiles[swap_index]
		candidate_tiles[swap_index] = tmp

	var spawn_count := mini(rng.randi_range(config.lithium_spawn_min, config.lithium_spawn_max), candidate_tiles.size())
	for index in range(spawn_count):
		_spawn_lithium_pickup_at(candidate_tiles[index], _world_generation_id)


func _on_water_pickup_collected(_item_data: Dictionary, _quantity: int, coords: Vector2i, generation_id: int) -> void:
	_schedule_water_respawn(coords, generation_id)


func _schedule_water_respawn(coords: Vector2i, generation_id: int) -> void:
	var timer := get_tree().create_timer(config.water_respawn_seconds)
	timer.timeout.connect(_respawn_water_pickup.bind(coords, generation_id), CONNECT_ONE_SHOT)


func _respawn_water_pickup(coords: Vector2i, generation_id: int) -> void:
	if generation_id != _world_generation_id:
		return
	if not _river_tile_coords.has(coords):
		return
	if ground_layer.get_cell_source_id(coords) == -1:
		return
	_spawn_water_pickup_at(coords, generation_id)


func _spawn_lithium_pickup_at(coords: Vector2i, generation_id: int) -> void:
	if element_spawn_system == null:
		return
	if element_spawn_system.has_method("get_pickup_at_tile"):
		var existing_pickup: Node2D = element_spawn_system.get_pickup_at_tile(coords)
		if existing_pickup != null:
			return
	if not element_spawn_system.has_method("spawn_element_at"):
		return
	var pickup: Node2D = element_spawn_system.spawn_element_at(&"lithium", coords, ground_layer)
	if pickup == null:
		return
	if pickup.has_signal("picked_up"):
		var callback := Callable(self, "_on_lithium_pickup_collected").bind(coords, generation_id)
		if not pickup.is_connected("picked_up", callback):
			pickup.connect("picked_up", callback, CONNECT_ONE_SHOT)


func _on_lithium_pickup_collected(_item_data: Dictionary, _quantity: int, coords: Vector2i, generation_id: int) -> void:
	_schedule_lithium_respawn(coords, generation_id)


func _schedule_lithium_respawn(coords: Vector2i, generation_id: int) -> void:
	var timer := get_tree().create_timer(config.lithium_respawn_seconds)
	timer.timeout.connect(_respawn_lithium_pickup.bind(coords, generation_id), CONNECT_ONE_SHOT)


func _respawn_lithium_pickup(coords: Vector2i, generation_id: int) -> void:
	if generation_id != _world_generation_id:
		return
	if not _iron_hills_lithium_deep_tiles.has(coords):
		return
	if ground_layer.get_cell_source_id(coords) == -1:
		return
	_spawn_lithium_pickup_at(coords, generation_id)


func get_movement_speed_multiplier_at_world_position(world_position: Vector2) -> float:
	if ground_layer == null:
		return 1.0
	var local_position := ground_layer.to_local(world_position)
	var coords := ground_layer.local_to_map(local_position)
	if _sodium_shoals_brine_tiles.has(coords):
		return config.sodium_shoals_brine_speed_multiplier
	if _sulfur_flats_cracked_tiles.has(coords):
		return config.sulfur_flats_cracked_speed_multiplier
	return 1.0


func is_water_at_world_position(world_position: Vector2) -> bool:
	if ground_layer == null:
		return false
	var local_position := ground_layer.to_local(world_position)
	var coords := ground_layer.local_to_map(local_position)
	return _river_tile_coords.has(coords)


func is_rain_blocked_at_world_position(world_position: Vector2) -> bool:
	if objects_layer == null:
		return false
	var local_position := objects_layer.to_local(world_position)
	var coords := objects_layer.local_to_map(local_position)
	return (
		_is_tree_canopy_tile(coords)
		or _is_tree_canopy_tile(coords + Vector2i(0, -1))
		or _is_tree_canopy_tile(coords + Vector2i(-1, -1))
		or _is_tree_canopy_tile(coords + Vector2i(1, -1))
	)


func is_sulfur_flats_at_world_position(world_position: Vector2) -> bool:
	if ground_layer == null:
		return false
	var local_position := ground_layer.to_local(world_position)
	var coords := ground_layer.local_to_map(local_position)
	return (
		_sulfur_flats_ash_tiles.has(coords)
		or _sulfur_flats_cracked_tiles.has(coords)
		or _sulfur_flats_lava_rock_tiles.has(coords)
	)


func _is_tree_canopy_tile(coords: Vector2i) -> bool:
	if objects_layer.get_cell_source_id(coords) != TREE_CANOPY_SOURCE_ID:
		return false
	return objects_layer.get_cell_atlas_coords(coords) == TREE_CANOPY_ATLAS_COORDS


func _get_sulfur_flats_blocked_tiles() -> Dictionary:
	var blocked_tiles: Dictionary = {}
	for coords: Vector2i in _sulfur_flats_ash_tiles.keys():
		blocked_tiles[coords] = true
	for coords: Vector2i in _sulfur_flats_cracked_tiles.keys():
		blocked_tiles[coords] = true
	for coords: Vector2i in _sulfur_flats_lava_rock_tiles.keys():
		blocked_tiles[coords] = true
	return blocked_tiles


func _get_all_blocked_tiles() -> Dictionary:
	var blocked_tiles := _get_sulfur_flats_blocked_tiles()
	for coords: Vector2i in _iron_hills_lithium_tiles.keys():
		blocked_tiles[coords] = true
	return blocked_tiles


func _get_all_spawn_blocked_tiles() -> Dictionary:
	var blocked_tiles := _get_all_blocked_tiles()
	for child in generated_tree_resources.get_children():
		var tree := child as TreeResource
		if tree == null:
			continue
		blocked_tiles[tree.tile_coords] = true
	return blocked_tiles


func export_tree_state() -> Dictionary:
	return tree_manager.export_state() if tree_manager != null else {}


func import_tree_state(active_tree_state: Array, pending_respawns: Array) -> void:
	if tree_manager != null:
		tree_manager.import_state(active_tree_state, pending_respawns)


func _get_sulfur_flats_ash_tile_array() -> Array[Vector2i]:
	var ash_tiles: Array[Vector2i] = []
	for coords: Vector2i in _sulfur_flats_ash_tiles.keys():
		ash_tiles.append(coords)
	return ash_tiles


func _get_sulfur_flats_spawn_tiles() -> Array[Vector2i]:
	var spawn_tiles: Array[Vector2i] = []
	for coords: Vector2i in _sulfur_flats_ash_tiles.keys():
		spawn_tiles.append(coords)
	for coords: Vector2i in _sulfur_flats_cracked_tiles.keys():
		spawn_tiles.append(coords)
	return spawn_tiles


func _get_iron_hills_lithium_spawn_tiles() -> Array[Vector2i]:
	var spawn_tiles: Array[Vector2i] = []
	for coords: Vector2i in _iron_hills_lithium_deep_tiles.keys():
		spawn_tiles.append(coords)
	return spawn_tiles


func _get_world_seed() -> int:
	var world_system := EventBus.get_world_system()
	var scene_path := _get_scene_path()
	if world_system != null and world_system.has_method("get_seed_for_scene") and not scene_path.is_empty():
		return int(world_system.get_seed_for_scene(scene_path))
	if world_system != null and world_system.has_method("get_seed"):
		return int(world_system.get_seed())
	return 0


func _set_world_seed(world_seed: int) -> void:
	var world_system := EventBus.get_world_system()
	var scene_path := _get_scene_path()
	if world_system != null and world_system.has_method("set_seed_for_scene") and not scene_path.is_empty():
		world_system.set_seed_for_scene(scene_path, world_seed)
	elif world_system != null and world_system.has_method("set_seed"):
		world_system.set_seed(world_seed)


func move_player_to_travel_entry(entry_point_id: StringName) -> bool:
	if entry_point_id.is_empty():
		return false
	var current_player := get_node_or_null("Player") as Node2D
	if current_player == null and GameManager != null:
		current_player = GameManager.get_player()
	if current_player == null:
		return false
	var travel_entries := get_node_or_null("TravelEntries")
	if travel_entries == null:
		return false
	var marker := travel_entries.get_node_or_null(String(entry_point_id)) as Node2D
	if marker == null:
		return false
	current_player.global_position = marker.global_position
	return true


func is_sulfur_flats_scene() -> bool:
	return world_profile == WorldProfile.SULFUR_FLATS


func get_sulfur_flats_marker_position() -> Vector2:
	if ground_layer == null:
		return Vector2.ZERO
	if world_profile == WorldProfile.SULFUR_FLATS:
		var center_tile := SULFUR_FLATS_ORIGIN + Vector2i(SULFUR_FLATS_SIZE.x / 2, SULFUR_FLATS_SIZE.y / 2)
		return ground_layer.to_global(ground_layer.map_to_local(center_tile))
	return ground_layer.to_global(ground_layer.map_to_local(OVERWORLD_SULFUR_TRAILHEAD_TILE))


func _get_scene_path() -> String:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		return str(current_scene.scene_file_path)
	return str(scene_file_path)


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
	if camera != null and camera.has_method("set_bounds"):
		camera.call("set_bounds", get_world_bounds())


func _setup_generation_components() -> void:
	terrain_generator = _ensure_generation_component("TerrainGenerator", _get_script(TERRAIN_GENERATOR_SCRIPT_PATH))
	prop_spawner = _ensure_generation_component("PropSpawner", _get_script(PROP_SPAWNER_SCRIPT_PATH))
	enemy_director = _ensure_generation_component("EnemyDirector", _get_script(ENEMY_DIRECTOR_SCRIPT_PATH))
	tree_manager = _ensure_generation_component("TreeManager", _get_script(TREE_MANAGER_SCRIPT_PATH))
	prop_spawner.configure(self, ground_layer, objects_layer, generated_zone_props)
	enemy_director.configure(self, ground_layer, generated_zone_props)
	tree_manager.configure(self, ground_layer, objects_layer, generated_tree_resources, element_spawn_system, config)


func _ensure_generation_component(node_name: String, component_script: Script) -> Node:
	var component := get_node_or_null(node_name)
	if component != null:
		return component
	component = Node.new()
	component.name = node_name
	component.set_script(component_script)
	add_child(component)
	return component


func _get_scene(scene_path: String) -> PackedScene:
	var scene := _scene_cache.get(scene_path) as PackedScene
	if scene == null:
		scene = load(scene_path) as PackedScene
		_scene_cache[scene_path] = scene
	return scene


func _get_script(script_path: String) -> Script:
	var script := _script_cache.get(script_path) as Script
	if script == null:
		script = load(script_path) as Script
		_script_cache[script_path] = script
	return script


func _ensure_generated_child(node_name: String) -> Node2D:
	var existing_node := get_node_or_null(node_name) as Node2D
	if existing_node != null:
		_position_generated_child(existing_node)
		return existing_node
	var node := Node2D.new()
	node.name = node_name
	add_child(node)
	_position_generated_child(node)
	return node


func _clear_generated_children(node: Node2D) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.free()


func _position_generated_child(node: Node2D) -> void:
	if node == null:
		return
	match node.name:
		"GeneratedZoneDecor":
			node.z_index = 0
			var ground_index := ground_layer.get_index() if ground_layer != null else 0
			move_child(node, mini(ground_index + 1, get_child_count() - 1))
		"GeneratedTreeResources":
			node.z_index = 4
			var objects_index := objects_layer.get_index() if objects_layer != null else get_child_count() - 1
			move_child(node, mini(objects_index + 1, get_child_count() - 1))
		"GeneratedZoneProps":
			node.z_index = 5
			var objects_index := objects_layer.get_index() if objects_layer != null else get_child_count() - 1
			move_child(node, mini(objects_index + 1, get_child_count() - 1))
