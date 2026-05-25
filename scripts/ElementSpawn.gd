extends Node2D

const ELEMENT_PICKUP_SCENE := preload("res://scenes/ElementPickup.tscn")
const ELEMENT_SPAWN_TABLE: Array[Dictionary] = [
	{
		&"id": &"wood",
		&"weight": 50,
		&"max_count": 20,
	},
	{
		&"id": &"stone",
		&"weight": 30,
		&"max_count": 12,
	},
	{
		&"id": &"iron",
		&"weight": 20,
		&"max_count": 8,
	},
	{
		# Water is river-only — spawned by WorldGen._spawn_water_pickups(), not the weighted picker.
		# Weight 0 keeps it out of random placement while still letting spawn_counts track it.
		&"id": &"water",
		&"weight": 0,
		&"max_count": 6,
	},
]


func spawn_elements(
	ground_layer: TileMapLayer,
	objects_layer: TileMapLayer,
	world_seed: int,
	blocked_tiles: Dictionary = {}
) -> Dictionary[StringName, int]:
	_clear_spawned_elements()

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 7919

	var spawn_counts := _create_spawn_count_table()
	var ground_cells := _get_shuffled_ground_cells(ground_layer, rng)

	for coords: Vector2i in ground_cells:
		if _are_all_caps_reached(spawn_counts):
			break

		if blocked_tiles.has(coords):
			continue

		if _is_blocked_by_collision_tile(objects_layer, coords):
			continue

		var element_id := _pick_weighted_element(rng, spawn_counts)
		if element_id.is_empty():
			break

		_spawn_element(element_id, coords, ground_layer)
		spawn_counts[element_id] += 1

	_log_spawn_report(spawn_counts, ground_cells.size(), objects_layer)
	return spawn_counts


func _clear_spawned_elements() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _create_spawn_count_table() -> Dictionary[StringName, int]:
	var spawn_counts: Dictionary[StringName, int] = {}
	for element_data: Dictionary in ELEMENT_SPAWN_TABLE:
		spawn_counts[element_data[&"id"]] = 0
	return spawn_counts


func _get_shuffled_ground_cells(ground_layer: TileMapLayer, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var ground_cells: Array[Vector2i] = []
	for coords: Vector2i in ground_layer.get_used_cells():
		ground_cells.append(coords)

	for index in range(ground_cells.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var current_coords := ground_cells[index]
		ground_cells[index] = ground_cells[swap_index]
		ground_cells[swap_index] = current_coords

	return ground_cells


func _is_blocked_by_collision_tile(objects_layer: TileMapLayer, coords: Vector2i) -> bool:
	return objects_layer.get_cell_source_id(coords) != -1


func _pick_weighted_element(rng: RandomNumberGenerator, spawn_counts: Dictionary[StringName, int]) -> StringName:
	var total_weight := 0
	for element_data: Dictionary in ELEMENT_SPAWN_TABLE:
		var element_id: StringName = element_data[&"id"]
		if spawn_counts[element_id] < element_data[&"max_count"]:
			total_weight += element_data[&"weight"]

	if total_weight <= 0:
		return &""

	var roll := rng.randi_range(1, total_weight)
	for element_data: Dictionary in ELEMENT_SPAWN_TABLE:
		var element_id: StringName = element_data[&"id"]
		if spawn_counts[element_id] >= element_data[&"max_count"]:
			continue

		roll -= element_data[&"weight"]
		if roll <= 0:
			return element_id

	return &""


func _spawn_element(element_id: StringName, coords: Vector2i, ground_layer: TileMapLayer) -> void:
	spawn_element_at(element_id, coords, ground_layer)


func spawn_element_at(element_id: StringName, coords: Vector2i, ground_layer: TileMapLayer) -> Node2D:
	var existing_pickup := get_pickup_at_tile(coords)
	if existing_pickup != null:
		return existing_pickup

	var pickup := _create_pickup(element_id, 1)
	pickup.name = "%s_%d_%d" % [element_id, coords.x, coords.y]
	pickup.set_meta(&"tile_coords", coords)
	add_child(pickup)
	pickup.global_position = ground_layer.to_global(ground_layer.map_to_local(coords))
	return pickup


func spawn_world_pickup(element_id: StringName, world_position: Vector2, quantity: int = 1) -> Node2D:
	if element_id.is_empty() or quantity <= 0:
		return null

	var pickup := _create_pickup(element_id, quantity)
	pickup.name = "%s_drop_%d" % [element_id, Time.get_ticks_usec()]
	add_child(pickup)
	pickup.global_position = world_position
	return pickup


func spawn_inventory_pickup(item_data: Dictionary, world_position: Vector2, quantity: int = 1) -> Node2D:
	if item_data.is_empty() or quantity <= 0:
		return null

	var pickup := _create_inventory_pickup(item_data, quantity)
	var item_id := StringName(str(item_data.get("id", "item")))
	pickup.name = "%s_drop_%d" % [item_id, Time.get_ticks_usec()]
	add_child(pickup)
	pickup.global_position = world_position
	return pickup


func get_pickup_at_tile(coords: Vector2i) -> Node2D:
	for child in get_children():
		if not child.has_meta(&"tile_coords"):
			continue
		if child.get_meta(&"tile_coords") == coords:
			return child as Node2D
	return null


func _are_all_caps_reached(spawn_counts: Dictionary[StringName, int]) -> bool:
	for element_data: Dictionary in ELEMENT_SPAWN_TABLE:
		var element_id: StringName = element_data[&"id"]
		if spawn_counts[element_id] < element_data[&"max_count"]:
			return false
	return true


func _log_spawn_report(spawn_counts: Dictionary[StringName, int], ground_cell_count: int, objects_layer: TileMapLayer) -> void:
	var runtime := get_tree().root.get_node_or_null("MCPRuntime")
	if runtime == null or not runtime.has_method("push_runtime_log"):
		return

	var report := {
		&"ground_tiles_checked": ground_cell_count,
		&"spawned": spawn_counts,
		&"total": _get_total_spawn_count(spawn_counts),
		&"blocked_tiles_used": _count_blocked_spawn_tiles(objects_layer),
	}
	runtime.push_runtime_log("info", "ElementSpawn report: %s" % JSON.stringify(report))


func _get_total_spawn_count(spawn_counts: Dictionary[StringName, int]) -> int:
	var total := 0
	for element_id: StringName in spawn_counts:
		total += spawn_counts[element_id]
	return total


func _count_blocked_spawn_tiles(objects_layer: TileMapLayer) -> int:
	var blocked_count := 0
	for child in get_children():
		if not child.has_meta(&"tile_coords"):
			continue

		var coords: Vector2i = child.get_meta(&"tile_coords")
		if _is_blocked_by_collision_tile(objects_layer, coords):
			blocked_count += 1

	return blocked_count


func _create_pickup(element_id: StringName, quantity: int) -> Node2D:
	var pickup := ELEMENT_PICKUP_SCENE.instantiate()
	pickup.set(&"element_id", element_id)
	pickup.set(&"pickup_quantity", quantity)
	pickup.set_meta(&"element_id", element_id)
	return pickup


func _create_inventory_pickup(item_data: Dictionary, quantity: int) -> Node2D:
	var pickup := ELEMENT_PICKUP_SCENE.instantiate()
	var payload := item_data.duplicate(true)
	payload.erase("quantity")
	pickup.set(&"pickup_quantity", quantity)
	pickup.set_meta(&"item_data", payload)
	if payload.has("id"):
		var item_id := StringName(str(payload.get("id", "")))
		pickup.set(&"element_id", item_id)
		pickup.set_meta(&"element_id", item_id)
	return pickup
