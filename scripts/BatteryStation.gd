extends StaticBody2D

const UI_SCENE := preload("res://scenes/UI/PowerSwitchboard.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $PromptLabel

var _player_in_range := false
var _is_interacting := false
var _interact_locked_until_release := false
var _player: Node
var _ui_instance: Node


func _ready() -> void:
	add_to_group(&"touch_interactable")
	_build_visual_identity()
	_configure_prompt_label()
	_ensure_ui()
	
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("interact"):
		_interact_locked_until_release = false
		return
	if _player_in_range and event.is_action_pressed("interact") and not _interact_locked_until_release:
		if _is_interacting:
			_close_ui()
		else:
			_open_ui()
		get_viewport().set_input_as_handled()


func _open_ui() -> void:
	if _ui_instance == null:
		return
	_is_interacting = true
	_interact_locked_until_release = true
	prompt_label.visible = false
	if _player != null and _player.has_method("pause_input"):
		_player.pause_input()
	_ui_instance.open()


func _close_ui() -> void:
	if not _is_interacting:
		return
	_is_interacting = false
	_interact_locked_until_release = true
	if _player_in_range:
		prompt_label.visible = true
	if _player != null and _player.has_method("resume_input"):
		_player.resume_input()
	if _ui_instance != null:
		_ui_instance.close()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player"):
		_player_in_range = true
		_player = body
		if not _is_interacting:
			prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group(&"player"):
		_player_in_range = false
		prompt_label.visible = false
		if _is_interacting:
			_close_ui()
		_player = null


func _configure_prompt_label() -> void:
	if prompt_label == null:
		return
	prompt_label.add_theme_font_size_override("font_size", 9)
	prompt_label.add_theme_color_override("font_color", Color.WHITE)
	prompt_label.add_theme_constant_override("outline_size", 2)
	prompt_label.visible = false
	
	var key_hint := "E"
	if MobileInputRouter.prefers_touch_controls():
		prompt_label.text = "Tap Interact to use Battery Station"
	else:
		if InputMap.has_action("interact"):
			var events := InputMap.action_get_events("interact")
			if not events.is_empty():
				key_hint = events[0].as_text()
		prompt_label.text = "[%s] Battery Station" % key_hint


func _ensure_ui() -> void:
	if _ui_instance != null:
		return
	
	var canvas := get_tree().root.get_node_or_null("World/HUD")
	if canvas == null:
		canvas = get_tree().root.get_node_or_null("World/CanvasLayer")
		if canvas == null:
			canvas = CanvasLayer.new()
			canvas.name = "BatteryStationCanvas"
			add_child(canvas)
			
	_ui_instance = UI_SCENE.instantiate()
	canvas.add_child(_ui_instance)
	_ui_instance.closed.connect(_close_ui)


func _build_visual_identity() -> void:
	if sprite == null:
		return
	sprite.texture = _build_placeholder_texture()
	sprite.offset = Vector2(0.0, -6.0)


func _build_placeholder_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(8, 26):
		for x in range(6, 26):
			image.set_pixel(x, y, Color(0.20, 0.24, 0.30, 1.0))

	for y in range(10, 24):
		for x in range(10, 22):
			image.set_pixel(x, y, Color(0.38, 0.48, 0.62, 1.0))

	for y in range(12, 22):
		for x in range(12, 20):
			image.set_pixel(x, y, Color(0.56, 0.86, 1.0, 0.95))

	for y in range(6, 10):
		for x in range(12, 20):
			image.set_pixel(x, y, Color(0.48, 0.50, 0.54, 1.0))

	for y in range(24, 30):
		for x in range(8, 12):
			image.set_pixel(x, y, Color(0.30, 0.22, 0.12, 1.0))
		for x in range(20, 24):
			image.set_pixel(x, y, Color(0.30, 0.22, 0.12, 1.0))

	for x in range(10, 22):
		image.set_pixel(x, 10, Color(0.82, 0.88, 0.95, 1.0))
		image.set_pixel(x, 23, Color(0.10, 0.14, 0.20, 1.0))

	return ImageTexture.create_from_image(image)


func can_touch_interact(player: Node2D) -> bool:
	return player != null and player == _player and _player_in_range and not _is_interacting


func get_touch_interaction_prompt() -> String:
	return "Use Battery Station"


func get_touch_interaction_world_position() -> Vector2:
	return global_position + Vector2(0.0, -28.0)


func perform_touch_interaction() -> void:
	if not _player_in_range or _is_interacting:
		return
	_open_ui()
