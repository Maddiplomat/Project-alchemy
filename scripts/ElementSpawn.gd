extends Node2D

const ELEMENT_PICKUP_SCENE := preload("res://scenes/ElementPickup.tscn")
func spawn_elements(
	ground_layer: TileMapLayer,
	objects_layer: TileMapLayer,
	world_seed: int,
	blocked_tiles: Dictionary = {}
) -> Dictionary[StringName, int]:
	_clear_spawned_elements()
	# WorldGen places water, sulfur, and lithium explicitly in authored locations.
	# Stone, iron, limestone, and wood come from their dedicated world sources instead
	# of being scattered as ambient pickups.
	return {}


func _clear_spawned_elements() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _spawn_element(element_id: StringName, coords: Vector2i, ground_layer: TileMapLayer) -> void:
	spawn_element_at(element_id, coords, ground_layer)


func spawn_element_at(element_id: StringName, coords: Vector2i, ground_layer: TileMapLayer) -> Node2D:
	var existing_pickup := get_pickup_at_tile(coords)
	if existing_pickup != null:
		return existing_pickup

	var pickup := _create_pickup(element_id, 1)
	pickup.name = "%s_%d_%d" % [element_id, coords.x, coords.y]
	pickup.set_meta(&"tile_coords", coords)
	pickup.set_meta(&"pickup_origin", &"resource_spawn")
	add_child(pickup)
	pickup.global_position = ground_layer.to_global(ground_layer.map_to_local(coords))
	return pickup


func spawn_world_pickup(element_id: StringName, world_position: Vector2, quantity: int = 1) -> Node2D:
	if element_id.is_empty() or quantity <= 0:
		return null

	var pickup := _create_pickup(element_id, quantity)
	pickup.name = "%s_drop_%d" % [element_id, Time.get_ticks_usec()]
	pickup.set_meta(&"pickup_origin", &"world_drop")
	add_child(pickup)
	pickup.global_position = world_position
	return pickup


func spawn_inventory_pickup(item_data: Dictionary, world_position: Vector2, quantity: int = 1) -> Node2D:
	if item_data.is_empty() or quantity <= 0:
		return null

	var pickup := _create_inventory_pickup(item_data, quantity)
	var item_id := StringName(str(item_data.get("id", "item")))
	pickup.name = "%s_drop_%d" % [item_id, Time.get_ticks_usec()]
	pickup.set_meta(&"pickup_origin", &"inventory_drop")
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
		if objects_layer.get_cell_source_id(coords) != -1:
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
