extends "res://scripts/PlacedObject.gd"

const WALL_COLOR := Color(0.50, 0.52, 0.56, 1.0)
const WALL_SHADE := Color(0.33, 0.35, 0.39, 1.0)
const WALL_HIGHLIGHT := Color(0.72, 0.74, 0.79, 1.0)
const WALL_SHADOW := Color(0.24, 0.26, 0.29, 1.0)
const TILE_SIZE := 16
const CORE_MIN := 4
const CORE_MAX := 11


func _ready() -> void:
	object_type = "wall"
	save_bucket = SaveBucket.WALLS
	super()
	call_deferred("refresh_wall_and_neighbors")


func refresh_wall_and_neighbors() -> void:
	_update_wall_visual()
	for neighbor in _get_adjacent_walls():
		if neighbor != null:
			neighbor._update_wall_visual()


func _update_wall_visual() -> void:
	if sprite == null:
		return

	var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var connections := {
		&"north": _has_connector_at(placed_at + Vector2i.UP),
		&"east": _has_connector_at(placed_at + Vector2i.RIGHT),
		&"south": _has_connector_at(placed_at + Vector2i.DOWN),
		&"west": _has_connector_at(placed_at + Vector2i.LEFT),
	}

	_fill_wall_rect(image, Rect2i(CORE_MIN, CORE_MIN, CORE_MAX - CORE_MIN + 1, CORE_MAX - CORE_MIN + 1))

	if connections[&"north"]:
		_fill_wall_rect(image, Rect2i(CORE_MIN, 0, CORE_MAX - CORE_MIN + 1, CORE_MIN + 1))
	if connections[&"south"]:
		_fill_wall_rect(image, Rect2i(CORE_MIN, CORE_MAX, CORE_MAX - CORE_MIN + 1, TILE_SIZE - CORE_MAX))
	if connections[&"west"]:
		_fill_wall_rect(image, Rect2i(0, CORE_MIN, CORE_MIN + 1, CORE_MAX - CORE_MIN + 1))
	if connections[&"east"]:
		_fill_wall_rect(image, Rect2i(CORE_MAX, CORE_MIN, TILE_SIZE - CORE_MAX, CORE_MAX - CORE_MIN + 1))

	_outline_wall_shape(image)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2.ZERO


func _fill_wall_rect(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color := WALL_COLOR if ((x / 4) + (y / 4)) % 2 == 0 else WALL_SHADE
			image.set_pixel(x, y, color)


func _outline_wall_shape(image: Image) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var color := image.get_pixel(x, y)
			if color.a <= 0.0:
				continue

			if _is_empty(image, x, y - 1):
				image.set_pixel(x, y, WALL_HIGHLIGHT)
			elif _is_empty(image, x - 1, y):
				image.set_pixel(x, y, WALL_HIGHLIGHT)
			elif _is_empty(image, x + 1, y):
				image.set_pixel(x, y, WALL_SHADOW)
			elif _is_empty(image, x, y + 1):
				image.set_pixel(x, y, WALL_SHADOW)


func _is_empty(image: Image, x: int, y: int) -> bool:
	if x < 0 or x >= TILE_SIZE or y < 0 or y >= TILE_SIZE:
		return true
	return image.get_pixel(x, y).a <= 0.0


func _get_adjacent_walls() -> Array:
	var results: Array = []
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var neighbor = _get_wall_at(placed_at + offset)
		if neighbor != null:
			results.append(neighbor)
	return results


func _has_connector_at(tile_coords: Vector2i) -> bool:
	return _get_wall_at(tile_coords) != null or _get_door_at(tile_coords) != null


func _get_wall_at(tile_coords: Vector2i):
	for node in get_tree().get_nodes_in_group(&"placed_walls"):
		if node == self or not is_instance_valid(node):
			continue
		if node.is_in_group(&"placed_doors"):
			continue
		if node.has_method("get_placed_tile_coords"):
			if node.call("get_placed_tile_coords") == tile_coords:
				return node
		elif node.has_meta(&"build_tile_coords") and node.get_meta(&"build_tile_coords") == tile_coords:
			return node
	return null


func _get_door_at(tile_coords: Vector2i):
	for node in get_tree().get_nodes_in_group(&"placed_doors"):
		if not is_instance_valid(node):
			continue
		if node.has_method("get_placed_tile_coords"):
			if node.call("get_placed_tile_coords") == tile_coords:
				return node
		elif node.has_meta(&"build_tile_coords") and node.get_meta(&"build_tile_coords") == tile_coords:
			return node
	return null


func get_placed_tile_coords() -> Vector2i:
	return placed_at
