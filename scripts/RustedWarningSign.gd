extends Node2D

const SIGN_TEXT := "Volatile Compounds\nEnter Prepared"

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label


func _ready() -> void:
	sprite.texture = _build_sign_texture()
	sprite.z_index = 20
	label.z_index = 21
	label.text = SIGN_TEXT


func _build_sign_texture() -> Texture2D:
	var image := Image.create(28, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(3, 17):
		for x in range(3, 25):
			image.set_pixel(x, y, Color(0.33, 0.19, 0.11, 1.0))

	for y in range(4, 16):
		for x in range(4, 24):
			image.set_pixel(x, y, Color(0.44, 0.28, 0.17, 1.0))

	for y in range(18, 31):
		for x in range(12, 16):
			image.set_pixel(x, y, Color(0.27, 0.20, 0.13, 1.0))

	for x in range(6, 22, 4):
		image.set_pixel(x, 6, Color(0.58, 0.32, 0.16, 1.0))
		image.set_pixel(x + 1, 7, Color(0.58, 0.32, 0.16, 1.0))

	for y in range(7, 13):
		for x in range(7, 21):
			if (x + y) % 5 == 0:
				image.set_pixel(x, y, Color(0.72, 0.67, 0.54, 0.85))

	return ImageTexture.create_from_image(image)
