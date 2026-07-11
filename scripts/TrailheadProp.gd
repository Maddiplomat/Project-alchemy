extends Area2D

const PANEL_BG := Color(0.08, 0.09, 0.11, 0.96)
const PANEL_EDGE := Color(0.60, 0.72, 0.84, 1.0)
const PANEL_TEXT := Color(0.93, 0.95, 0.97, 1.0)
const PANEL_SUBTEXT := Color(0.72, 0.80, 0.87, 1.0)

@export var prompt_text := "Tap Interact to travel"
@export var trail_name := "Trailhead"
@export_multiline var travel_blurb := "This route leaves the base behind. Pack for the return trip before committing."
@export var target_scene_path := ""
@export var target_entry_point_id: StringName = &""

@onready var sprite: Sprite2D = $Sprite2D
@onready var prompt_label: Label = $PromptLabel

var _player_in_range: CharacterBody2D = null
var _overlay: Control = null
var _overlay_visible := false


func _ready() -> void:
	add_to_group(&"touch_interactable")
	sprite.texture = _build_sign_texture()
	sprite.z_index = 20
	prompt_label.z_index = 21
	prompt_label.text = _get_runtime_prompt_text()
	prompt_label.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _overlay_visible:
		if event.is_action_pressed("interact"):
			_confirm_travel()
			_mark_input_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_overlay()
			_mark_input_handled()
		return

	if _player_in_range == null:
		return
	if event.is_action_pressed("interact"):
		_open_overlay()
		_mark_input_handled()


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D) or not body.is_in_group(&"player"):
		return
	_player_in_range = body as CharacterBody2D
	if not _overlay_visible:
		prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if body != _player_in_range:
		return
	_player_in_range = null
	if not _overlay_visible:
		prompt_label.visible = false


func _open_overlay() -> void:
	_ensure_overlay()
	if _overlay == null:
		return
	_overlay_visible = true
	_overlay.visible = true
	prompt_label.visible = false
	if _player_in_range != null and _player_in_range.has_method("pause_input"):
		_player_in_range.pause_input()


func _close_overlay() -> void:
	_overlay_visible = false
	if _overlay != null:
		_overlay.visible = false
	if _player_in_range != null and _player_in_range.has_method("resume_input"):
		_player_in_range.resume_input()
	prompt_label.visible = _player_in_range != null


func _confirm_travel() -> void:
	if target_scene_path.is_empty():
		_close_overlay()
		return
	if WorldSystem != null and WorldSystem.has_method("travel_to_scene"):
		var travel_started := bool(WorldSystem.travel_to_scene(target_scene_path, target_entry_point_id))
		if travel_started:
			_overlay_visible = false
			return
	_close_overlay()


func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var ui_parent := current_scene.find_child("HUD", true, false)
	if ui_parent == null:
		ui_parent = current_scene

	var overlay := Control.new()
	overlay.name = "%sOverlay" % name
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.54)
	overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220.0
	panel.offset_top = -108.0
	panel.offset_right = 220.0
	panel.offset_bottom = 108.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = PANEL_EDGE
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var title_label := Label.new()
	title_label.text = trail_name
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", PANEL_TEXT)
	layout.add_child(title_label)

	var body_label := Label.new()
	body_label.text = travel_blurb
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body_label.add_theme_font_size_override("font_size", 17)
	body_label.add_theme_color_override("font_color", PANEL_TEXT)
	layout.add_child(body_label)

	var footer_label := Label.new()
	footer_label.text = "Tap Travel to depart. Tap Stay to cancel."
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_label.add_theme_font_size_override("font_size", 14)
	footer_label.add_theme_color_override("font_color", PANEL_SUBTEXT)
	layout.add_child(footer_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	layout.add_child(actions)

	var stay_button := Button.new()
	stay_button.text = "Stay"
	stay_button.pressed.connect(_close_overlay)
	actions.add_child(stay_button)

	var travel_button := Button.new()
	travel_button.text = "Travel"
	travel_button.pressed.connect(_confirm_travel)
	actions.add_child(travel_button)

	ui_parent.add_child(overlay)
	_overlay = overlay


func _build_sign_texture() -> Texture2D:
	var image := Image.create(32, 34, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(4, 18):
		for x in range(3, 29):
			image.set_pixel(x, y, Color(0.24, 0.28, 0.32, 1.0))

	for y in range(5, 17):
		for x in range(4, 28):
			image.set_pixel(x, y, Color(0.36, 0.43, 0.49, 1.0))

	for y in range(19, 33):
		for x in range(13, 19):
			image.set_pixel(x, y, Color(0.26, 0.20, 0.14, 1.0))

	for x in range(7, 25, 4):
		image.set_pixel(x, 8, Color(0.80, 0.90, 0.99, 0.95))
		image.set_pixel(x + 1, 9, Color(0.80, 0.90, 0.99, 0.95))

	return ImageTexture.create_from_image(image)


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func can_touch_interact(player: Node2D) -> bool:
	return player != null and player == _player_in_range and not _overlay_visible


func get_touch_interaction_prompt() -> String:
	return "Travel" if String(trail_name).findn("Return") == -1 else "Return"


func get_touch_interaction_world_position() -> Vector2:
	return global_position + Vector2(0.0, -26.0)


func perform_touch_interaction() -> void:
	if _player_in_range == null or _overlay_visible:
		return
	_open_overlay()


func _get_runtime_prompt_text() -> String:
	if MobileInputRouter.prefers_touch_controls():
		return "Tap Interact to travel" if String(prompt_text).findn("return") == -1 else "Tap Interact to return"
	return prompt_text
