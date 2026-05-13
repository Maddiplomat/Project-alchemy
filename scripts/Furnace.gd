extends StaticBody2D

const FURNACE_UI_SCENE := preload("res://scenes/UI/FurnaceUI.tscn")

signal player_entered_range
signal player_exited_range
signal interaction_started
signal interaction_ended

@export var is_lit := false
@export var fuel_level := 0.0
@export var current_temp := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $PromptLabel

var _unlit_texture: Texture2D
var _lit_texture: Texture2D
var _player_in_range := false
var _is_interacting := false
var _interact_locked_until_release := false
var _player: Node
var _furnace_ui


func _ready() -> void:
	_unlit_texture = _build_placeholder_texture(false)
	_lit_texture = _build_placeholder_texture(true)
	_update_sprite()
	_ensure_ui()
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_hide_prompt()


func _process(_delta: float) -> void:
	if _interact_locked_until_release:
		if not Input.is_action_pressed("interact"):
			_interact_locked_until_release = false
		return
	if _player_in_range and not _is_interacting:
		if Input.is_action_just_pressed("interact"):
			_start_interaction()


func set_lit(value: bool) -> void:
	is_lit = value
	_update_sprite()


func open_ui() -> void:
	_is_interacting = true
	_interact_locked_until_release = true
	_show_prompt(false)
	if is_instance_valid(_player) and _player.has_method("pause_input"):
		_player.pause_input()
	_ensure_ui()
	if _furnace_ui != null:
		_furnace_ui.open_ui()
	interaction_started.emit()


func close_ui() -> void:
	if not _is_interacting:
		return
	_is_interacting = false
	_interact_locked_until_release = true
	_show_prompt(_player_in_range)
	if _furnace_ui != null and _furnace_ui.visible:
		_furnace_ui.close_ui()
	if is_instance_valid(_player) and _player.has_method("resume_input"):
		_player.resume_input()
	interaction_ended.emit()


func _start_interaction() -> void:
	open_ui()


func _on_body_entered(body: Node) -> void:
	if body.name == "Player" and body is CharacterBody2D:
		_player = body
		_player_in_range = true
		if not _is_interacting:
			_show_prompt(true)
		player_entered_range.emit()


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		if body == _player:
			_player = null
		_player_in_range = false
		_hide_prompt()
		player_exited_range.emit()


func _show_prompt(show: bool) -> void:
	if prompt_label:
		prompt_label.visible = show


func _hide_prompt() -> void:
	if prompt_label:
		prompt_label.visible = false


func _ensure_ui() -> void:
	if _furnace_ui != null:
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var ui_parent := current_scene.find_child("HUD", true, false)
	if ui_parent == null:
		ui_parent = current_scene

	_furnace_ui = FURNACE_UI_SCENE.instantiate()
	ui_parent.add_child(_furnace_ui)
	_furnace_ui.ui_closed.connect(_on_ui_closed)


func _on_ui_closed() -> void:
	close_ui()


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
