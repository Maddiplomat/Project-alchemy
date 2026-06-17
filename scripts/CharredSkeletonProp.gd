extends Node2D

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	sprite.texture = _build_texture()
	sprite.z_index = 18


func _build_texture() -> Texture2D:
	var image := Image.create(30, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var bone_shadow := Color(0.08, 0.07, 0.06, 0.92)
	var ash := Color(0.23, 0.21, 0.19, 0.65)
	var ember := Color(0.67, 0.29, 0.13, 0.35)

	for y in range(11, 15):
		for x in range(3, 25):
			if (x + y) % 2 == 0:
				image.set_pixel(x, y, ash)

	for y in range(4, 8):
		for x in range(19, 23):
			image.set_pixel(x, y, bone_shadow)

	for x in range(9, 20):
		image.set_pixel(x, 8, bone_shadow)
	for x in range(10, 18):
		image.set_pixel(x, 9, bone_shadow)

	for y in range(6, 12):
		image.set_pixel(14, y, bone_shadow)
		image.set_pixel(15, y, bone_shadow)

	for offset in range(5):
		image.set_pixel(10 - offset, 9 + offset, bone_shadow)
		image.set_pixel(18 + offset, 9 + offset, bone_shadow)
		image.set_pixel(12 - offset, 8 + offset, bone_shadow)
		image.set_pixel(17 + offset, 8 + offset, bone_shadow)

	for offset in range(4):
		image.set_pixel(13 - offset, 12 + offset, bone_shadow)
		image.set_pixel(16 + offset, 12 + offset, bone_shadow)

	for x in range(5, 12):
		image.set_pixel(x, 14, ash)
	for x in range(17, 24):
		image.set_pixel(x, 14, ash)

	image.set_pixel(6, 13, ember)
	image.set_pixel(21, 12, ember)
	image.set_pixel(23, 14, ember)

	return ImageTexture.create_from_image(image)
