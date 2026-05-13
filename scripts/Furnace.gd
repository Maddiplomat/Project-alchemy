extends StaticBody2D

signal player_entered_range
signal player_exited_range

@export var is_lit := false
@export var fuel_level := 0.0
@export var current_temp := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea

var _unlit_texture: Texture2D
var _lit_texture: Texture2D


func _ready() -> void:
	_unlit_texture = _build_placeholder_texture(false)
	_lit_texture = _build_placeholder_texture(true)
	_update_sprite()
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)


func set_lit(value: bool) -> void:
	is_lit = value
	_update_sprite()


func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		player_entered_range.emit()


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		player_exited_range.emit()


func _update_sprite() -> void:
	if sprite == null:
		return
	sprite.texture = _lit_texture if is_lit else _unlit_texture


func _build_placeholder_texture(lit: bool) -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var brick := Color8(92, 88, 80)
	var shadow := Color8(54, 50, 45)
	var top := Color8(124, 118, 108)
	var mouth := Color8(28, 23, 20)
	var glow := Color8(255, 145, 50)
	var ember := Color8(255, 215, 110)

	for y in range(6, 29):
		for x in range(5, 27):
			image.set_pixel(x, y, brick)

	for y in range(6, 10):
		for x in range(8, 24):
			image.set_pixel(x, y, top)

	for y in range(10, 29):
		image.set_pixel(5, y, shadow)
		image.set_pixel(26, y, shadow)

	for x in range(5, 27):
		image.set_pixel(x, 28, shadow)

	for y in range(15, 25):
		for x in range(10, 22):
			image.set_pixel(x, y, mouth)

	var fire_color := glow if lit else shadow
	for y in range(17, 24):
		for x in range(12, 20):
			image.set_pixel(x, y, fire_color)

	if lit:
		for y in range(19, 22):
			for x in range(14, 18):
				image.set_pixel(x, y, ember)

	for y in range(3, 7):
		for x in range(20, 24):
			image.set_pixel(x, y, shadow)

	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
