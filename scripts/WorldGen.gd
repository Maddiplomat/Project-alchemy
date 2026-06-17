extends Node2D

const MAP_SIZE := Vector2i(64, 64)
const TILE_SIZE := 16
const SOURCE_ID := 0
const GRASS_TILE := Vector2i(0, 0)
const TREE_TILE := Vector2i(1, 1)
const ROCK_TILE := Vector2i(2, 1)
const WATER_TILE := Vector2i(3, 0)
const SULFUR_FLATS_SIZE := Vector2i(10, 10)
const IRON_HILLS_LITHIUM_SIZE := Vector2i(10, 9)
const SULFUR_FLATS_CRACKED_SPEED_MULTIPLIER := 0.7
const SULFUR_MIN_SPAWNS := 8
const SULFUR_MAX_SPAWNS := 12
const LITHIUM_MIN_SPAWNS := 5
const LITHIUM_MAX_SPAWNS := 6
const SPARSE_TREE_MIN := 0.62
const DENSE_TREE_MIN := 0.78
const HARVESTABLE_TREE_COUNT := 20
const TREE_RESPAWN_SECONDS := 600.0
const TREE_RESPAWN_RETRY_SECONDS := 30.0
const ELEMENT_SPAWN_SYSTEM_SCRIPT := preload("res://scripts/ElementSpawn.gd")
const RUSTED_WARNING_SIGN_SCENE := preload("res://scenes/RustedWarningSign.tscn")
const CHARRED_SKELETON_PROP_SCENE := preload("res://scenes/CharredSkeletonProp.tscn")
const SCORCHED_CRATE_NOTE_SCENE := preload("res://scenes/ScorchedCrateNote.tscn")
const STONE_QUARRY_SCENE := preload("res://scenes/StoneQuarry.tscn")
const IRON_MINE_SCENE := preload("res://scenes/IronMine.tscn")
const LIMESTONE_MINE_SCENE := preload("res://scenes/LimestoneMine.tscn")
const ACID_CRAWLER_SPAWNER_SCENE := preload("res://scenes/AcidCrawlerSpawner.tscn")
const BATTERY_STATION_SCENE := preload("res://scenes/BatteryStation.tscn")
const TREE_RESOURCE_SCENE := preload("res://scenes/TreeResource.tscn")
const WATER_RESPAWN_SECONDS := 120.0
const LITHIUM_RESPAWN_SECONDS := 210.0
const TREE_CANOPY_SOURCE_ID := SOURCE_ID
const TREE_CANOPY_ATLAS_COORDS := TREE_TILE
const IRON_MINE_COORDS := Vector2i(12, 8)

var _river_tile_coords: Array[Vector2i] = []
var _sulfur_flats_ash_tiles: Dictionary = {}
var _sulfur_flats_cracked_tiles: Dictionary = {}
var _sulfur_flats_lava_rock_tiles: Dictionary = {}
var _iron_hills_lithium_tiles: Dictionary = {}
var _iron_hills_lithium_deep_tiles: Dictionary = {}
var _world_generation_id := 0
var _tree_respawn_deadlines: Dictionary = {}
var _next_tree_respawn_id := 0
var _tree_spawn_sequence := 0

@export var generate_on_ready := true
@export var noise_frequency := 0.08
@export_range(0.0, 1.0, 0.01) var sparse_tree_density := 0.20

@onready var ground_layer: TileMapLayer = $Ground
@onready var decor_layer: TileMapLayer = $Decor
@onready var objects_layer: TileMapLayer = $Objects
@onready var element_spawn_system := get_node_or_null("ElementSpawnSystem") as Node2D
@onready var sulfur_flats_zone := get_node_or_null("SulfurFlatsZone") as Node2D
@onready var generated_zone_decor := _ensure_generated_child("GeneratedZoneDecor")
@onready var generated_zone_props := _ensure_generated_child("GeneratedZoneProps")
@onready var generated_tree_resources := _ensure_generated_child("GeneratedTreeResources")


func _ready() -> void:
	_prepare_element_spawn_system()
	if generate_on_ready:
		generate_world(_get_world_seed())
	_wire_camera_bounds()


func generate_world(world_seed: int) -> void:
	_world_generation_id += 1
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

	_place_sulfur_flats_zone()
	_place_iron_hills_lithium_zone()
	_place_river_cluster(world_seed)
	_place_acid_crawler_spawn(world_seed)
	_place_stone_quarry(world_seed)
	_place_iron_mines(world_seed)
	_place_limestone_mine(world_seed)
	_place_battery_station(world_seed)
	_spawn_interactive_trees(world_seed)
	_spawn_elements(world_seed)
	_spawn_sulfur_crystals(world_seed)
	_spawn_lithium_deposits(world_seed)
	_spawn_water_pickups(world_seed)


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
	_tree_respawn_deadlines.clear()
	_clear_generated_children(generated_zone_decor)
	_clear_generated_children(generated_zone_props)
	_clear_generated_children(generated_tree_resources)


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


func _place_stone_quarry(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 12345

	var coords := Vector2i.ZERO
	for _attempt in range(12):
		var q_x := rng.randi_range(6, MAP_SIZE.x / 4)
		var q_y := rng.randi_range(6, MAP_SIZE.y / 4)
		coords = Vector2i(q_x, q_y)
		if coords.distance_to(IRON_MINE_COORDS) >= 7.0:
			break

	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var clear_coords := coords + Vector2i(dx, dy)
			if not _is_edge(clear_coords):
				objects_layer.erase_cell(clear_coords)

	var quarry := STONE_QUARRY_SCENE.instantiate()
	quarry.position = ground_layer.to_global(ground_layer.map_to_local(coords))
	generated_zone_props.add_child(quarry)


func _place_battery_station(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 99999

	# Place near spawn area (centre) but slightly offset so it's clearly visible
	var centre := MAP_SIZE / 2
	var offsets: Array[Vector2i] = [
		Vector2i(-5, -4),
		Vector2i(5, -4),
		Vector2i(-5, 4),
		Vector2i(5, 4),
	]
	var offset_idx := rng.randi_range(0, offsets.size() - 1)
	var coords: Vector2i = centre + offsets[offset_idx]

	# Clear a small area so the station isn't buried in trees
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var clear: Vector2i = coords + Vector2i(dx, dy)
			if not _is_edge(clear):
				objects_layer.erase_cell(clear)

	var station := BATTERY_STATION_SCENE.instantiate()
	station.position = ground_layer.to_global(ground_layer.map_to_local(coords))
	generated_zone_props.add_child(station)


func _place_iron_mines(world_seed: int) -> void:
	if generated_zone_props == null:
		return
	_clear_tree_patch(IRON_MINE_COORDS, 1, 1)
	var mine := IRON_MINE_SCENE.instantiate()
	mine.position = ground_layer.to_global(ground_layer.map_to_local(IRON_MINE_COORDS))
	generated_zone_props.add_child(mine)


func _place_limestone_mine(world_seed: int) -> void:
	if generated_zone_props == null or _river_tile_coords.is_empty():
		return
	
	var min_x := MAP_SIZE.x
	var target_y := MAP_SIZE.y / 2
	for coords in _river_tile_coords:
		if coords.x < min_x:
			min_x = coords.x
			target_y = coords.y

	# Place it to the left of the river
	var mine_x := maxi(min_x - 4, 3)
	var coords := Vector2i(mine_x, target_y)

	# Clear surrounding objects (like trees)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var clear_coords := coords + Vector2i(dx, dy)
			if not _is_edge(clear_coords):
				objects_layer.erase_cell(clear_coords)

	var mine := LIMESTONE_MINE_SCENE.instantiate()
	mine.position = ground_layer.to_global(ground_layer.map_to_local(coords))
	generated_zone_props.add_child(mine)


func _place_acid_crawler_spawn(world_seed: int) -> void:
	if generated_zone_props == null or ACID_CRAWLER_SPAWNER_SCENE == null:
		return
	if _river_tile_coords.is_empty():
		return

	var spawn_coords := _find_acid_crawler_spawn_tile(world_seed)
	if spawn_coords == Vector2i(-1, -1):
		return

	_clear_tree_patch(spawn_coords, 1, 1)
	var spawn_world_position := ground_layer.to_global(ground_layer.map_to_local(spawn_coords))
	var spawner := ACID_CRAWLER_SPAWNER_SCENE.instantiate()
	spawner.name = "AcidCrawlerSpawner"
	spawner.position = spawn_world_position
	spawner.set("spawn_position", spawn_world_position)
	generated_zone_props.add_child(spawner)


func _find_acid_crawler_spawn_tile(world_seed: int) -> Vector2i:
	var sulfur_origin := MAP_SIZE - SULFUR_FLATS_SIZE
	var south_band_min_y := MAP_SIZE.y - 12
	var river_anchor := Vector2i(-1, -1)
	for coords: Vector2i in _river_tile_coords:
		if coords.y < south_band_min_y:
			continue
		if coords.x > river_anchor.x:
			river_anchor = coords

	var min_x := maxi(river_anchor.x + 3, sulfur_origin.x - 12)
	var max_x := sulfur_origin.x - 2
	if min_x > max_x:
		min_x = sulfur_origin.x - 8
		max_x = sulfur_origin.x - 2

	var candidates: Array[Vector2i] = []
	for y in range(MAP_SIZE.y - 5, south_band_min_y - 1, -1):
		for x in range(min_x, max_x + 1):
			var coords := Vector2i(x, y)
			if not _can_place_acid_crawler_at(coords):
				continue
			candidates.append(coords)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_score := _score_acid_crawler_spawn_tile(a, sulfur_origin)
		var b_score := _score_acid_crawler_spawn_tile(b, sulfur_origin)
		if is_equal_approx(a_score, b_score):
			return a.x > b.x
		return a_score > b_score
	)
	return candidates[0]


func _score_acid_crawler_spawn_tile(coords: Vector2i, sulfur_origin: Vector2i) -> float:
	var sulfur_bias := float(coords.x - sulfur_origin.x)
	var south_bias := float(coords.y)
	return sulfur_bias * 3.0 + south_bias


func _can_place_acid_crawler_at(coords: Vector2i) -> bool:
	if _is_edge(coords) or _is_spawn_area(coords):
		return false
	if _river_tile_coords.has(coords):
		return false
	if _get_all_blocked_tiles().has(coords):
		return false
	if objects_layer.get_cell_source_id(coords) != -1:
		return false
	return true


func _spawn_interactive_trees(world_seed: int) -> void:
	var candidate_tiles := _get_harvestable_tree_candidates()
	if candidate_tiles.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 55123
	for index in range(candidate_tiles.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidate_tiles[index]
		candidate_tiles[index] = candidate_tiles[swap_index]
		candidate_tiles[swap_index] = tmp

	var spawn_count := mini(HARVESTABLE_TREE_COUNT, candidate_tiles.size())
	for index in range(spawn_count):
		_spawn_interactive_tree_at(candidate_tiles[index], 10)


func _get_harvestable_tree_candidates() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var blocked_tiles := _get_all_blocked_tiles()
	for coords: Vector2i in objects_layer.get_used_cells():
		if not _is_tree_canopy_tile(coords):
			continue
		if blocked_tiles.has(coords):
			continue
		candidates.append(coords)
	return candidates


func _spawn_interactive_tree_at(coords: Vector2i, stock: int) -> TreeResource:
	if generated_tree_resources == null:
		return null
	var existing_tree := _get_tree_at_tile(coords)
	if existing_tree != null:
		existing_tree.configure(coords, stock)
		return existing_tree
	if _is_tree_canopy_tile(coords):
		objects_layer.erase_cell(coords)
	var tree := TREE_RESOURCE_SCENE.instantiate() as TreeResource
	if tree == null:
		return null
	tree.name = "Tree_%d_%d" % [coords.x, coords.y]
	tree.position = ground_layer.map_to_local(coords)
	tree.configure(coords, stock)
	generated_tree_resources.add_child(tree)
	tree.depleted.connect(_on_tree_depleted.bind(_world_generation_id))
	return tree


func _get_tree_at_tile(coords: Vector2i) -> TreeResource:
	if generated_tree_resources == null:
		return null
	for child in generated_tree_resources.get_children():
		var tree := child as TreeResource
		if tree == null:
			continue
		if tree.tile_coords == coords:
			return tree
	return null


func _on_tree_depleted(tree: TreeResource, generation_id: int) -> void:
	if generation_id != _world_generation_id:
		return
	if tree != null and is_instance_valid(tree):
		tree.queue_free()
	_schedule_tree_respawn(generation_id, TREE_RESPAWN_SECONDS)
	GameManager.mark_dirty()


func _schedule_tree_respawn(generation_id: int, delay_seconds: float) -> void:
	_next_tree_respawn_id += 1
	var respawn_id := _next_tree_respawn_id
	var clamped_delay := maxf(0.0, delay_seconds)
	_tree_respawn_deadlines[respawn_id] = Time.get_ticks_msec() + int(round(clamped_delay * 1000.0))
	var timer := get_tree().create_timer(clamped_delay)
	timer.timeout.connect(_respawn_tree.bind(respawn_id, generation_id), CONNECT_ONE_SHOT)


func _respawn_tree(respawn_id: int, generation_id: int) -> void:
	if generation_id != _world_generation_id:
		return
	if not _tree_respawn_deadlines.has(respawn_id):
		return
	_tree_respawn_deadlines.erase(respawn_id)
	var coords := _find_random_tree_spawn_tile()
	if coords == Vector2i(-1, -1):
		_schedule_tree_respawn(generation_id, TREE_RESPAWN_RETRY_SECONDS)
		return
	_spawn_interactive_tree_at(coords, 10)
	GameManager.mark_dirty()


func _find_random_tree_spawn_tile() -> Vector2i:
	var rng := RandomNumberGenerator.new()
	_tree_spawn_sequence += 1
	rng.seed = _get_world_seed() + (_world_generation_id * 4099) + _tree_spawn_sequence + Time.get_ticks_msec()
	var candidates: Array[Vector2i] = []
	for coords: Vector2i in ground_layer.get_used_cells():
		candidates.append(coords)
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = tmp
	for coords: Vector2i in candidates:
		if _can_spawn_tree_at(coords):
			return coords
	return Vector2i(-1, -1)


func _can_spawn_tree_at(coords: Vector2i) -> bool:
	if ground_layer == null or ground_layer.get_cell_source_id(coords) == -1:
		return false
	if _is_edge(coords) or _is_spawn_area(coords):
		return false
	if _river_tile_coords.has(coords):
		return false
	if _get_all_blocked_tiles().has(coords):
		return false
	if objects_layer != null and objects_layer.get_cell_source_id(coords) != -1:
		return false
	if _get_tree_at_tile(coords) != null:
		return false
	if element_spawn_system != null and element_spawn_system.has_method("get_pickup_at_tile"):
		if element_spawn_system.get_pickup_at_tile(coords) != null:
			return false
	if BuildSystem != null and BuildSystem.has_method("_has_placed_object_at_tile"):
		if BuildSystem.call("_has_placed_object_at_tile", self, coords):
			return false
	return not _has_tree_overlap_at_world_position(ground_layer.to_global(ground_layer.map_to_local(coords)))


func _has_tree_overlap_at_world_position(world_position: Vector2) -> bool:
	var query_shape := CircleShape2D.new()
	query_shape.radius = 9.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = query_shape
	query.transform = Transform2D(0.0, world_position)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.collision_mask = 1
	var world_2d := get_world_2d()
	if world_2d == null:
		return false
	for hit in world_2d.direct_space_state.intersect_shape(query, 16):
		var collider := hit.get("collider") as Node
		if collider == null:
			continue
		if collider == ground_layer or collider == objects_layer:
			continue
		return true
	return false


func _place_sulfur_flats_zone() -> void:
	var zone_origin := MAP_SIZE - SULFUR_FLATS_SIZE
	var zone_rect := Rect2i(zone_origin, SULFUR_FLATS_SIZE)
	var boundary_y := zone_origin.y + (SULFUR_FLATS_SIZE.y / 2)

	for y in range(zone_rect.position.y, zone_rect.end.y):
		for x in range(zone_rect.position.x, zone_rect.end.x):
			var coords := Vector2i(x, y)
			objects_layer.erase_cell(coords)

			if _is_sulfur_lava_rock_tile(zone_rect, coords):
				objects_layer.set_cell(coords, SOURCE_ID, ROCK_TILE, 0)
				_sulfur_flats_lava_rock_tiles[coords] = true
			elif _is_sulfur_cracked_tile(zone_rect, coords):
				_sulfur_flats_cracked_tiles[coords] = true
			else:
				_sulfur_flats_ash_tiles[coords] = true

			_draw_sulfur_tile(coords)

	var sign_tile := Vector2i(zone_origin.x - 2, boundary_y - 2)
	var skeleton_tile := Vector2i(zone_origin.x - 1, boundary_y + 1)
	var crate_tile := Vector2i(zone_origin.x - 3, boundary_y)
	_clear_tree_patch(sign_tile, 1, 1)
	_clear_tree_patch(skeleton_tile, 1, 1)
	_clear_tree_patch(crate_tile, 1, 1)

	var sign := RUSTED_WARNING_SIGN_SCENE.instantiate()
	generated_zone_props.add_child(sign)
	sign.position = ground_layer.map_to_local(sign_tile) + Vector2(0.0, -4.0)

	var charred_skeleton := CHARRED_SKELETON_PROP_SCENE.instantiate()
	generated_zone_props.add_child(charred_skeleton)
	charred_skeleton.position = ground_layer.map_to_local(skeleton_tile) + Vector2(-2.0, 4.0)

	var scorched_crate := SCORCHED_CRATE_NOTE_SCENE.instantiate()
	generated_zone_props.add_child(scorched_crate)
	scorched_crate.position = ground_layer.map_to_local(crate_tile) + Vector2(0.0, 2.0)

	if sulfur_flats_zone != null and sulfur_flats_zone.has_method("configure_zone"):
		sulfur_flats_zone.configure_zone(ground_layer, _get_sulfur_flats_ash_tile_array())


func _place_iron_hills_lithium_zone() -> void:
	var zone_origin := Vector2i(MAP_SIZE.x - IRON_HILLS_LITHIUM_SIZE.x, 0)
	var zone_rect := Rect2i(zone_origin, IRON_HILLS_LITHIUM_SIZE)

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
	if local_coords.x >= IRON_HILLS_LITHIUM_SIZE.x or local_coords.y >= IRON_HILLS_LITHIUM_SIZE.y:
		return false

	# Shape an inset quarry pocket so the lithium area reads as an Iron Hills sub-zone, not a map-edge stamp.
	if local_coords.x <= 0 or local_coords.y <= 0:
		return false
	if local_coords.x >= IRON_HILLS_LITHIUM_SIZE.x - 1 or local_coords.y >= IRON_HILLS_LITHIUM_SIZE.y - 1:
		return false
	if local_coords.x == 1 and local_coords.y <= 2:
		return false
	if local_coords.x <= 2 and local_coords.y == 1:
		return false
	if local_coords.x >= IRON_HILLS_LITHIUM_SIZE.x - 3 and local_coords.y == 1:
		return false
	if local_coords.x == IRON_HILLS_LITHIUM_SIZE.x - 2 and local_coords.y == 2:
		return false
	if local_coords.y >= IRON_HILLS_LITHIUM_SIZE.y - 2 and local_coords.x == 1:
		return false
	return true


func _is_iron_hills_lithium_deep_tile(zone_rect: Rect2i, coords: Vector2i) -> bool:
	var local_coords := coords - zone_rect.position
	if not _is_iron_hills_lithium_zone_tile(zone_rect, coords):
		return false
	if local_coords.x <= 2 or local_coords.y <= 2:
		return false
	if local_coords.x >= IRON_HILLS_LITHIUM_SIZE.x - 2 or local_coords.y >= IRON_HILLS_LITHIUM_SIZE.y - 2:
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
	var puddle_tile := zone_origin + Vector2i(1, IRON_HILLS_LITHIUM_SIZE.y - 2)
	var charred_tile := puddle_tile + Vector2i(1, -1)
	_clear_tree_patch(puddle_tile, 1, 1)
	_clear_tree_patch(charred_tile, 1, 1)

	var puddle := _build_rain_warning_puddle()
	generated_zone_props.add_child(puddle)
	puddle.position = ground_layer.map_to_local(puddle_tile) + Vector2(0.0, 3.0)

	var charred_deposit := _build_charred_lithium_deposit_prop()
	generated_zone_props.add_child(charred_deposit)
	charred_deposit.position = ground_layer.map_to_local(charred_tile) + Vector2(0.0, 1.0)


func _get_iron_hills_lithium_local_coords(coords: Vector2i) -> Vector2i:
	var zone_origin := Vector2i(MAP_SIZE.x - IRON_HILLS_LITHIUM_SIZE.x, 0)
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
	if local_coords.x <= 1 and abs(local_coords.y - (SULFUR_FLATS_SIZE.y / 2)) <= 1:
		return false
	if local_coords.x >= SULFUR_FLATS_SIZE.x - 2 or local_coords.y >= SULFUR_FLATS_SIZE.y - 2:
		return false
	return (local_coords.x + local_coords.y) % 3 == 0 or (
		local_coords.x >= 3 and local_coords.x <= 6 and local_coords.y >= 2 and local_coords.y <= 7
	)


func _is_sulfur_lava_rock_tile(zone_rect: Rect2i, coords: Vector2i) -> bool:
	var local_coords := coords - zone_rect.position
	if local_coords.x >= SULFUR_FLATS_SIZE.x - 2:
		return true
	if local_coords.y >= SULFUR_FLATS_SIZE.y - 2:
		return true
	if local_coords.x >= 6 and local_coords.y >= 5:
		return true
	if local_coords.x == 3 and local_coords.y == 1:
		return true
	return false


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

	var spawn_count := mini(rng.randi_range(SULFUR_MIN_SPAWNS, SULFUR_MAX_SPAWNS), candidate_tiles.size())
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

	var spawn_count := mini(rng.randi_range(LITHIUM_MIN_SPAWNS, LITHIUM_MAX_SPAWNS), candidate_tiles.size())
	for index in range(spawn_count):
		_spawn_lithium_pickup_at(candidate_tiles[index], _world_generation_id)


func _on_water_pickup_collected(_item_data: Dictionary, _quantity: int, coords: Vector2i, generation_id: int) -> void:
	_schedule_water_respawn(coords, generation_id)


func _schedule_water_respawn(coords: Vector2i, generation_id: int) -> void:
	var timer := get_tree().create_timer(WATER_RESPAWN_SECONDS)
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
	var timer := get_tree().create_timer(LITHIUM_RESPAWN_SECONDS)
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
	if _sulfur_flats_cracked_tiles.has(coords):
		return SULFUR_FLATS_CRACKED_SPEED_MULTIPLIER
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
	var active_tree_state: Array[Dictionary] = []
	if generated_tree_resources != null:
		for child in generated_tree_resources.get_children():
			var tree := child as TreeResource
			if tree == null:
				continue
			active_tree_state.append(tree.export_state())

	var pending_respawns: Array[Dictionary] = []
	var now_msec := Time.get_ticks_msec()
	for respawn_id in _tree_respawn_deadlines.keys():
		var deadline_msec := int(_tree_respawn_deadlines[respawn_id])
		var remaining_seconds := maxf(0.0, float(deadline_msec - now_msec) / 1000.0)
		pending_respawns.append({
			&"remaining_seconds": remaining_seconds,
		})

	return {
		&"active_trees": active_tree_state,
		&"pending_tree_respawns": pending_respawns,
	}


func import_tree_state(active_tree_state: Array, pending_respawns: Array) -> void:
	_tree_respawn_deadlines.clear()
	_clear_generated_children(generated_tree_resources)
	for entry in active_tree_state:
		if not (entry is Dictionary):
			continue
		var coords := _dict_to_coords(entry.get("tile_coords", {}))
		if coords == Vector2i(-1, -1):
			continue
		var remaining_wood := clampi(int(entry.get("remaining_wood", 10)), 1, 10)
		_spawn_interactive_tree_at(coords, remaining_wood)
	for entry in pending_respawns:
		if not (entry is Dictionary):
			continue
		var remaining_seconds := maxf(0.0, float(entry.get("remaining_seconds", TREE_RESPAWN_SECONDS)))
		_schedule_tree_respawn(_world_generation_id, remaining_seconds)


func _dict_to_coords(raw_coords: Variant) -> Vector2i:
	if not (raw_coords is Dictionary):
		return Vector2i(-1, -1)
	var coords := raw_coords as Dictionary
	return Vector2i(int(coords.get("x", -1)), int(coords.get("y", -1)))


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
	if camera != null and camera.has_method("set_bounds"):
		camera.call("set_bounds", get_world_bounds())


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
		child.queue_free()


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
