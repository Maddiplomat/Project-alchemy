extends "res://scripts/PlacedObject.gd"

const SHELTER_RADIUS_TILES := 1
const ROOF_COLOR := Color(0.33, 0.27, 0.18, 1.0)
const ROOF_HIGHLIGHT := Color(0.66, 0.56, 0.34, 1.0)
const POST_COLOR := Color(0.22, 0.16, 0.10, 1.0)


func _ready() -> void:
	object_type = "shelter_roof"
	save_bucket = SaveBucket.STATIONS
	add_to_group(&"shelter_roof")
	_build_visual_identity()
	super()
	if collision_shape != null:
		collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	z_index = 24


func get_shelter_tile_coords() -> Array[Vector2i]:
	var covered_tiles: Array[Vector2i] = []
	for y in range(-SHELTER_RADIUS_TILES, SHELTER_RADIUS_TILES + 1):
		for x in range(-SHELTER_RADIUS_TILES, SHELTER_RADIUS_TILES + 1):
			covered_tiles.append(placed_at + Vector2i(x, y))
	return covered_tiles


func covers_tile(tile_coords: Vector2i) -> bool:
	return abs(tile_coords.x - placed_at.x) <= SHELTER_RADIUS_TILES \
		and abs(tile_coords.y - placed_at.y) <= SHELTER_RADIUS_TILES


func get_occupied_tile_coords() -> Array[Vector2i]:
	return []


func _build_visual_identity() -> void:
	if sprite == null:
		return

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(6, 12):
		for x in range(4, 28):
			var color := ROOF_HIGHLIGHT if (x + y) % 4 == 0 else ROOF_COLOR
			image.set_pixel(x, y, color)

	for y in range(12, 15):
		for x in range(6, 26):
			image.set_pixel(x, y, ROOF_COLOR.darkened(0.12))

	for y in range(14, 28):
		for x in range(7, 10):
			image.set_pixel(x, y, POST_COLOR)
		for x in range(22, 25):
			image.set_pixel(x, y, POST_COLOR)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2(0.0, -10.0)
