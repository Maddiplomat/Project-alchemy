extends "res://scripts/buildings/StorageBuildingBase.gd"

const LOCKER_BODY := Color(0.18, 0.21, 0.24, 1.0)
const LOCKER_DOOR := Color(0.26, 0.30, 0.35, 1.0)
const LOCKER_TRIM := Color(0.82, 0.66, 0.22, 1.0)
const LOCKER_SHADOW := Color(0.10, 0.12, 0.14, 1.0)


func _get_object_type() -> String:
	return "volatile_locker"


func _get_container_title() -> String:
	return "Volatile Locker"


func _get_prompt_text() -> String:
	return "Tap Interact to open Volatile Locker" if MobileInputRouter.prefers_touch_controls() else "Press E to open Volatile Locker"


func _get_storage_filter_id() -> StringName:
	return StorageManager.FILTER_VOLATILE_ELEMENTS


func _build_storage_texture() -> void:
	if sprite == null:
		return

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(7, 28):
		for x in range(7, 25):
			image.set_pixel(x, y, LOCKER_BODY)

	for y in range(9, 26):
		for x in range(10, 22):
			image.set_pixel(x, y, LOCKER_DOOR)

	for x in range(7, 25):
		image.set_pixel(x, 7, LOCKER_TRIM)
		image.set_pixel(x, 27, LOCKER_SHADOW)

	for y in range(7, 28):
		image.set_pixel(7, y, LOCKER_SHADOW)
		image.set_pixel(24, y, LOCKER_SHADOW)

	for y in range(12, 22):
		image.set_pixel(15, y, LOCKER_TRIM)
		image.set_pixel(16, y, LOCKER_TRIM)

	for pos: Vector2i in [Vector2i(13, 17), Vector2i(18, 17)]:
		image.set_pixel(pos.x, pos.y, LOCKER_TRIM)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2(0.0, -2.0)
