extends Node2D

const MAP_SIZE := Vector2i(64, 64)
const TILE_SIZE := 16
const SOURCE_ID := 0
const GRASS_TILE := Vector2i(0, 0)
const TREE_TILE := Vector2i(1, 1)
const ROCK_TILE := Vector2i(2, 1)
const WATER_TILE := Vector2i(3, 0)
const SULFUR_FLATS_SIZE := Vector2i(10, 10)
const SULFUR_FLATS_CRACKED_SPEED_MULTIPLIER := 0.7
const SULFUR_MIN_SPAWNS := 8
const SULFUR_MAX_SPAWNS := 12
const SPARSE_TREE_MIN := 0.3
const DENSE_TREE_MIN := 0.6
const ELEMENT_SPAWN_SYSTEM_SCRIPT := preload("res://scripts/ElementSpawn.gd")
const RUSTED_WARNING_SIGN_SCENE := preload("res://scenes/RustedWarningSign.tscn")
const CHARRED_SKELETON_PROP_SCENE := preload("res://scenes/CharredSkeletonProp.tscn")
const SCORCHED_CRATE_NOTE_SCENE := preload("res://scenes/ScorchedCrateNote.tscn")
const WATER_RESPAWN_SECONDS := 120.0

var _river_tile_coords: Array[Vector2i] = []
var _sulfur_flats_ash_tiles: Dictionary = {}
var _sulfur_flats_cracked_tiles: Dictionary = {}
var _sulfur_flats_lava_rock_tiles: Dictionary = {}
var _world_generation_id := 0

@export var generate_on_ready := true
@export var noise_frequency := 0.08
@export_range(0.0, 1.0, 0.01) var sparse_tree_density := 0.35

@onready var ground_layer: TileMapLayer = $Ground
@onready var decor_layer: TileMapLayer = $Decor
@onready var objects_layer: TileMapLayer = $Objects
@onready var element_spawn_system := get_node_or_null("ElementSpawnSystem") as Node2D
@onready var sulfur_flats_zone := get_node_or_null("SulfurFlatsZone") as Node2D
@onready var generated_zone_decor := _ensure_generated_child("GeneratedZoneDecor")
@onready var generated_zone_props := _ensure_generated_child("GeneratedZoneProps")


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
	_place_river_cluster(world_seed)
	_spawn_elements(world_seed)
	_spawn_sulfur_crystals(world_seed)
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
	_clear_generated_children(generated_zone_decor)
	_clear_generated_children(generated_zone_props)


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
			_get_sulfur_flats_blocked_tiles()
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


func get_movement_speed_multiplier_at_world_position(world_position: Vector2) -> float:
	if ground_layer == null:
		return 1.0
	var local_position := ground_layer.to_local(world_position)
	var coords := ground_layer.local_to_map(local_position)
	if _sulfur_flats_cracked_tiles.has(coords):
		return SULFUR_FLATS_CRACKED_SPEED_MULTIPLIER
	return 1.0


func _get_sulfur_flats_blocked_tiles() -> Dictionary:
	var blocked_tiles: Dictionary = {}
	for coords: Vector2i in _sulfur_flats_ash_tiles.keys():
		blocked_tiles[coords] = true
	for coords: Vector2i in _sulfur_flats_cracked_tiles.keys():
		blocked_tiles[coords] = true
	for coords: Vector2i in _sulfur_flats_lava_rock_tiles.keys():
		blocked_tiles[coords] = true
	return blocked_tiles


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
		"GeneratedZoneProps":
			node.z_index = 5
			var objects_index := objects_layer.get_index() if objects_layer != null else get_child_count() - 1
			move_child(node, mini(objects_index + 1, get_child_count() - 1))
