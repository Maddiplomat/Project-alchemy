extends "res://scripts/buildings/StorageBuildingBase.gd"

const BOX_BODY := Color(0.45, 0.34, 0.22, 1.0)
const BOX_LID := Color(0.63, 0.54, 0.39, 1.0)
const BOX_TRIM := Color(0.48, 0.78, 0.95, 1.0)
const BOX_SHADOW := Color(0.22, 0.15, 0.09, 1.0)


func _get_object_type() -> String:
	return "dry_box"


func _get_container_title() -> String:
	return "Dry Box"


func _get_prompt_text() -> String:
	return "Press E to open Dry Box"


func _get_storage_filter_id() -> StringName:
	return StorageManager.FILTER_WATER_REACTIVE_ELEMENTS


func _build_storage_texture() -> void:
	if sprite == null:
		return

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(13, 26):
		for x in range(5, 27):
			image.set_pixel(x, y, BOX_BODY)

	for y in range(9, 14):
		for x in range(6, 26):
			image.set_pixel(x, y, BOX_LID)

	for x in range(5, 27):
		image.set_pixel(x, 13, BOX_TRIM)
		image.set_pixel(x, 25, BOX_SHADOW)

	for y in range(13, 26):
		image.set_pixel(5, y, BOX_SHADOW)
		image.set_pixel(26, y, BOX_SHADOW)

	for x in range(9, 23):
		image.set_pixel(x, 10, BOX_TRIM)

	for y in range(15, 22):
		image.set_pixel(15, y, BOX_TRIM)
		image.set_pixel(16, y, BOX_TRIM)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2(0.0, -2.0)
