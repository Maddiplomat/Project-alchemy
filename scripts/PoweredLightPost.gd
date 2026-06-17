extends "res://scripts/PlacedObject.gd"

const POST_DARK := Color(0.10, 0.12, 0.13, 1.0)
const POST_MID := Color(0.26, 0.30, 0.32, 1.0)
const POST_LIGHT := Color(0.72, 0.88, 0.92, 1.0)
const POST_GLOW := Color(0.36, 0.92, 1.0, 1.0)


func _ready() -> void:
	object_type = "powered_light_post"
	save_bucket = SaveBucket.STATIONS
	super()
	_build_light_post_texture()
	call_deferred("_refresh_powered_light")


func _refresh_powered_light() -> void:
	var powered_light: Node = get_node_or_null("PointLight2D")
	if powered_light != null and powered_light.has_method("_refresh_power_state"):
		powered_light.call("_refresh_power_state")


func _build_light_post_texture() -> void:
	if sprite == null:
		return

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(9, 29):
		for x in range(14, 18):
			image.set_pixel(x, y, POST_MID)
	for y in range(27, 31):
		for x in range(10, 22):
			image.set_pixel(x, y, POST_DARK)
	for y in range(6, 11):
		for x in range(9, 23):
			image.set_pixel(x, y, POST_LIGHT)
	for y in range(7, 10):
		for x in range(11, 21):
			image.set_pixel(x, y, POST_GLOW)
	for y in range(11, 14):
		for x in range(12, 20):
			image.set_pixel(x, y, POST_DARK)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2(0.0, -4.0)
