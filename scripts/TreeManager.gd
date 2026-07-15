class_name TreeManager
extends Node

const TREE_RESOURCE_SCENE := preload("res://scenes/TreeResource.tscn")
const DEFAULT_CONFIG: WorldGenConfig = preload("res://data/config/world_gen_config.tres")

var host: Node2D
var ground_layer: TileMapLayer
var objects_layer: TileMapLayer
var generated_tree_resources: Node2D
var element_spawn_system: Node2D
var config: WorldGenConfig = DEFAULT_CONFIG
var generation_id := 0
var _respawn_deadlines: Dictionary = {}
var _next_respawn_id := 0
var _spawn_sequence := 0


func configure(owner: Node2D, ground: TileMapLayer, objects: TileMapLayer, tree_root: Node2D, element_spawner: Node2D, world_config: WorldGenConfig = DEFAULT_CONFIG) -> void:
	host = owner
	ground_layer = ground
	objects_layer = objects
	generated_tree_resources = tree_root
	element_spawn_system = element_spawner
	config = world_config if world_config != null else DEFAULT_CONFIG


func begin_generation(new_generation_id: int) -> void:
	generation_id = new_generation_id
	_respawn_deadlines.clear()
	_spawn_sequence = 0


func spawn_interactive_trees(world_seed: int) -> void:
	var candidate_tiles := _get_candidates()
	if candidate_tiles.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 55123
	for index in range(candidate_tiles.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidate_tiles[index]
		candidate_tiles[index] = candidate_tiles[swap_index]
		candidate_tiles[swap_index] = tmp
	for index in range(mini(config.harvestable_tree_count, candidate_tiles.size())):
		_spawn_tree_at(candidate_tiles[index], 10)


func _get_candidates() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var blocked_tiles: Dictionary = host.call("_get_all_blocked_tiles")
	for coords: Vector2i in objects_layer.get_used_cells():
		if not bool(host.call("_is_tree_canopy_tile", coords)) or blocked_tiles.has(coords):
			continue
		candidates.append(coords)
	return candidates


func _spawn_tree_at(coords: Vector2i, stock: int) -> TreeResource:
	if generated_tree_resources == null:
		return null
	var existing_tree := _get_tree_at_tile(coords)
	if existing_tree != null:
		existing_tree.configure(coords, stock)
		return existing_tree
	if bool(host.call("_is_tree_canopy_tile", coords)):
		objects_layer.erase_cell(coords)
	var tree := TREE_RESOURCE_SCENE.instantiate() as TreeResource
	if tree == null:
		return null
	tree.name = "Tree_%d_%d" % [coords.x, coords.y]
	tree.position = ground_layer.map_to_local(coords)
	tree.configure(coords, stock)
	generated_tree_resources.add_child(tree)
	tree.depleted.connect(_on_tree_depleted.bind(generation_id))
	return tree


func _get_tree_at_tile(coords: Vector2i) -> TreeResource:
	if generated_tree_resources == null:
		return null
	for child in generated_tree_resources.get_children():
		var tree := child as TreeResource
		if tree != null and not tree.is_queued_for_deletion() and tree.tile_coords == coords:
			return tree
	return null


func _on_tree_depleted(tree: TreeResource, tree_generation_id: int) -> void:
	if tree_generation_id != generation_id:
		return
	if tree != null and is_instance_valid(tree):
		tree.queue_free()
		_schedule_respawn(tree_generation_id, config.tree_respawn_seconds)
	GameManager.mark_dirty()


func _schedule_respawn(tree_generation_id: int, delay_seconds: float) -> void:
	_next_respawn_id += 1
	var respawn_id := _next_respawn_id
	var delay := maxf(0.0, delay_seconds)
	_respawn_deadlines[respawn_id] = Time.get_ticks_msec() + int(round(delay * 1000.0))
	get_tree().create_timer(delay).timeout.connect(_respawn_tree.bind(respawn_id, tree_generation_id), CONNECT_ONE_SHOT)


func _respawn_tree(respawn_id: int, tree_generation_id: int) -> void:
	if tree_generation_id != generation_id or not _respawn_deadlines.has(respawn_id):
		return
	_respawn_deadlines.erase(respawn_id)
	var coords := _find_random_spawn_tile()
	if coords == Vector2i(-1, -1):
		_schedule_respawn(tree_generation_id, config.tree_respawn_retry_seconds)
		return
	_spawn_tree_at(coords, 10)
	GameManager.mark_dirty()


func _find_random_spawn_tile() -> Vector2i:
	var rng := RandomNumberGenerator.new()
	_spawn_sequence += 1
	rng.seed = int(host.call("_get_world_seed")) + generation_id * 4099 + _spawn_sequence + Time.get_ticks_msec()
	var candidates: Array[Vector2i] = ground_layer.get_used_cells()
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var tmp: Vector2i = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = tmp
	for coords in candidates:
		if _can_spawn_at(coords):
			return coords
	return Vector2i(-1, -1)


func _can_spawn_at(coords: Vector2i) -> bool:
	if ground_layer == null or ground_layer.get_cell_source_id(coords) == -1:
		return false
	if bool(host.call("_is_edge", coords)) or bool(host.call("_is_spawn_area", coords)):
		return false
	if host._river_tile_coords.has(coords) or (host.call("_get_all_blocked_tiles") as Dictionary).has(coords):
		return false
	if objects_layer.get_cell_source_id(coords) != -1 or _get_tree_at_tile(coords) != null:
		return false
	if element_spawn_system != null and element_spawn_system.has_method("get_pickup_at_tile") \
		and element_spawn_system.get_pickup_at_tile(coords) != null:
		return false
	var build_system := EventBus.get_build_system()
	if build_system != null and build_system.has_method("_has_placed_object_at_tile") \
		and build_system.call("_has_placed_object_at_tile", host, coords):
		return false
	return not _has_physics_overlap(ground_layer.to_global(ground_layer.map_to_local(coords)))


func _has_physics_overlap(world_position: Vector2) -> bool:
	var query_shape := CircleShape2D.new()
	query_shape.radius = 9.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = query_shape
	query.transform = Transform2D(0.0, world_position)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.collision_mask = 1
	var world_2d := host.get_world_2d()
	if world_2d == null:
		return false
	for hit in world_2d.direct_space_state.intersect_shape(query, 16):
		var collider := hit.get("collider") as Node
		if collider != null and collider != ground_layer and collider != objects_layer:
			return true
	return false


func export_state() -> Dictionary:
	var active: Array[Dictionary] = []
	if generated_tree_resources != null:
		for child in generated_tree_resources.get_children():
			var tree := child as TreeResource
			if tree != null:
				active.append(tree.export_state())
	var pending: Array[Dictionary] = []
	var now := Time.get_ticks_msec()
	for respawn_id in _respawn_deadlines:
		pending.append({&"remaining_seconds": maxf(0.0, float(int(_respawn_deadlines[respawn_id]) - now) / 1000.0)})
	return {&"active_trees": active, &"pending_tree_respawns": pending}


func import_state(active: Array, pending: Array) -> void:
	if active.is_empty() and pending.is_empty():
		return
	_respawn_deadlines.clear()
	for child in generated_tree_resources.get_children():
		child.queue_free()
	for entry in active:
		if not entry is Dictionary:
			continue
		var raw_coords := entry.get("tile_coords", {}) as Dictionary
		var coords := Vector2i(int(raw_coords.get("x", -1)), int(raw_coords.get("y", -1)))
		if coords != Vector2i(-1, -1):
			_spawn_tree_at(coords, clampi(int(entry.get("remaining_wood", 10)), 1, 10))
	for entry in pending:
		if entry is Dictionary:
			_schedule_respawn(generation_id, maxf(0.0, float(entry.get("remaining_seconds", config.tree_respawn_seconds))))
