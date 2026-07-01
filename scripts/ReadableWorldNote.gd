extends Area2D

const PANEL_BG := Color(0.10, 0.08, 0.06, 0.96)
const PANEL_EDGE := Color(0.56, 0.39, 0.21, 1.0)
const PANEL_TEXT := Color(0.94, 0.88, 0.77, 1.0)
const PANEL_SUBTEXT := Color(0.78, 0.70, 0.59, 1.0)

@export var prompt_text := "Press E to read note"
@export var note_title := "Scorched Supply Crate"
@export_multiline var note_text := "Left the sulfur in my pack. Got low on health near the vents. Never made it back."
@export var discovery_entry_id: StringName = &"sulfur_flats_carrier_warning"
@export var discovery_title := "Sulfur Flats Warning"
@export_multiline var discovery_notes := "Left the sulfur in my pack. Got low on health near the vents. Never made it back."

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var prompt_label: Label = $PromptLabel

var _player_in_range: CharacterBody2D = null
var _note_overlay: Control = null
var _note_visible := false


func _ready() -> void:
	sprite.texture = _build_texture()
	sprite.z_index = 18
	prompt_label.text = prompt_text
	prompt_label.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	if _note_overlay != null and is_instance_valid(_note_overlay):
		_note_overlay.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _note_visible:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_close_note()
			get_viewport().set_input_as_handled()
		return

	if _player_in_range != null and not _is_player_still_in_range():
		_player_in_range = null
		prompt_label.visible = false

	if _player_in_range == null:
		return
	if event.is_action_pressed("interact"):
		_open_note()
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = body as CharacterBody2D
	if not _note_visible:
		prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if body != _player_in_range:
		return
	_player_in_range = null
	if not _note_visible:
		prompt_label.visible = false


func _open_note() -> void:
	_ensure_note_overlay()
	if _note_overlay == null:
		return

	_note_visible = true
	_note_overlay.visible = true
	prompt_label.visible = false
	if _player_in_range != null and _player_in_range.has_method("pause_input"):
		_player_in_range.pause_input()
	DiscoveryLog.log_environment(discovery_entry_id, discovery_title, discovery_notes, true)


func _close_note() -> void:
	_note_visible = false
	if _note_overlay != null:
		_note_overlay.visible = false
	if _player_in_range != null and _player_in_range.has_method("resume_input"):
		_player_in_range.resume_input()
	prompt_label.visible = _player_in_range != null


func _is_player_body(body: Node) -> bool:
	return body is CharacterBody2D and body.is_in_group(&"player")


func _is_player_still_in_range() -> bool:
	if _player_in_range == null or not is_instance_valid(_player_in_range):
		return false
	var max_distance := _get_interaction_range()
	return global_position.distance_to(_player_in_range.global_position) <= max_distance


func _get_interaction_range() -> float:
	if collision_shape == null or collision_shape.shape == null:
		return 40.0
	if collision_shape.shape is RectangleShape2D:
		var rect_shape := collision_shape.shape as RectangleShape2D
		return rect_shape.size.length() * 0.5 + 12.0
	if collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape as CircleShape2D
		return circle_shape.radius + 12.0
	return 40.0


func _ensure_note_overlay() -> void:
	if _note_overlay != null and is_instance_valid(_note_overlay):
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
	shade.color = Color(0.0, 0.0, 0.0, 0.46)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -210.0
	panel.offset_top = -120.0
	panel.offset_right = 210.0
	panel.offset_bottom = 120.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = PANEL_EDGE
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var title_label := Label.new()
	title_label.text = note_title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", PANEL_TEXT)
	layout.add_child(title_label)

	var body_label := Label.new()
	body_label.text = note_text
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body_label.add_theme_font_size_override("font_size", 18)
	body_label.add_theme_color_override("font_color", PANEL_TEXT)
	layout.add_child(body_label)

	var footer_label := Label.new()
	footer_label.text = "Press E or Esc to close"
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_label.add_theme_font_size_override("font_size", 14)
	footer_label.add_theme_color_override("font_color", PANEL_SUBTEXT)
	layout.add_child(footer_label)

	ui_parent.add_child(overlay)
	_note_overlay = overlay


func _build_texture() -> Texture2D:
	var image := Image.create(30, 26, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var crate := Color(0.27, 0.18, 0.11, 1.0)
	var plank := Color(0.40, 0.26, 0.15, 1.0)
	var scorch := Color(0.11, 0.08, 0.06, 0.92)
	var ash := Color(0.31, 0.28, 0.26, 0.55)
	var paper := Color(0.82, 0.76, 0.60, 0.92)

	for y in range(8, 22):
		for x in range(4, 26):
			image.set_pixel(x, y, crate)

	for x in range(4, 26):
		image.set_pixel(x, 8, plank)
		image.set_pixel(x, 14, plank)
		image.set_pixel(x, 21, scorch)

	for y in range(9, 21):
		image.set_pixel(4, y, plank)
		image.set_pixel(25, y, scorch)
		image.set_pixel(14, y, plank)

	for y in range(4, 10):
		for x in range(16, 24):
			image.set_pixel(x, y, paper)

	for y in range(5, 9):
		image.set_pixel(16, y, scorch)
		image.set_pixel(23, y, scorch)

	for y in range(10, 22):
		for x in range(3, 27):
			if (x * 3 + y) % 11 == 0:
				image.set_pixel(x, y, ash)

	image.set_pixel(8, 19, scorch)
	image.set_pixel(10, 18, scorch)
	image.set_pixel(21, 16, scorch)

	return ImageTexture.create_from_image(image)
