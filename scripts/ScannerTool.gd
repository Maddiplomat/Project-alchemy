extends Node2D

## ScannerTool — attached to the Player node.
## Press and hold Q to reveal floating info panels for nearby pickups and enemies.

const ELEMENT_SCAN_RADIUS: float = 80.0
const ENEMY_SCAN_RADIUS: float = 120.0
const AUTO_DISMISS: float = 3.0
const ELEMENT_SCAN_DURATION: float = 0.4
const ENEMY_SCAN_DURATION: float = 1.2

## Visual tweak constants
const ELEMENT_PANEL_WIDTH: float = 140.0
const ELEMENT_PANEL_HEIGHT: float = 76.0
const ELEMENT_PANEL_OFFSET: Vector2 = Vector2(12.0, -64.0)
const ENEMY_PANEL_WIDTH: float = 220.0
const ENEMY_PANEL_HEIGHT: float = 148.0
const ENEMY_PANEL_OFFSET: Vector2 = Vector2(-88.0, -132.0)
const ENEMY_PANEL_ACCENT: Color = Color(0.36, 0.96, 1.0, 1.0)

const CATEGORY_COLOURS: Dictionary = {
	"organic": Color(0.45, 0.80, 0.30, 1.0),
	"mineral": Color(0.60, 0.60, 0.60, 1.0),
	"metal": Color(0.75, 0.80, 0.90, 1.0),
	"volatile": Color(1.00, 0.55, 0.15, 1.0),
	"gas": Color(0.55, 0.90, 1.00, 1.0),
	"radioactive": Color(0.40, 1.00, 0.10, 1.0),
	"catalyst": Color(1.00, 0.85, 0.20, 1.0),
}
const FALLBACK_COLOUR: Color = Color(0.85, 0.85, 0.85, 1.0)
const ENEMY_QUERY_MASK := 0x7fffffff

var _active_panels: Dictionary = {}
var _panel_offsets: Dictionary = {}
var _timers: Dictionary = {}
var _scanning: bool = false

@onready var _anim: AnimationPlayer = $ToolAnimationPlayer

var _space_state: PhysicsDirectSpaceState2D


func _ready() -> void:
	_space_state = get_world_2d().direct_space_state
	_setup_animations()


func _setup_animations() -> void:
	var anim_lib := AnimationLibrary.new()
	var scan_anim := Animation.new()

	var scale_idx := scan_anim.add_track(Animation.TYPE_VALUE)
	scan_anim.track_set_path(scale_idx, "ScannerToolVisuals/ScanRipple:scale")
	scan_anim.track_insert_key(scale_idx, 0.0, Vector2.ZERO)
	scan_anim.track_insert_key(scale_idx, ELEMENT_SCAN_DURATION, Vector2.ONE)

	var alpha_idx := scan_anim.add_track(Animation.TYPE_VALUE)
	scan_anim.track_set_path(alpha_idx, "ScannerToolVisuals/ScanRipple:modulate:a")
	scan_anim.track_insert_key(alpha_idx, 0.0, 1.0)
	scan_anim.track_insert_key(alpha_idx, ELEMENT_SCAN_DURATION, 0.0)

	var vis_idx := scan_anim.add_track(Animation.TYPE_VALUE)
	scan_anim.track_set_path(vis_idx, "ScannerToolVisuals/ScanRipple:visible")
	scan_anim.track_insert_key(vis_idx, 0.0, true)
	scan_anim.track_insert_key(vis_idx, ELEMENT_SCAN_DURATION, false)

	anim_lib.add_animation("scan", scan_anim)
	_anim.add_animation_library("", anim_lib)


func _input(event: InputEvent) -> void:
	var runtime := get_tree().root.get_node_or_null("MCPRuntime")
	if event.is_action_pressed("scan"):
		if runtime:
			runtime.push_runtime_log("info", "ScannerTool: Scan Pressed")
		_begin_scan()
	elif event.is_action_released("scan"):
		_end_scan()


func _process(delta: float) -> void:
	if not _scanning:
		return

	var expired: Array = []
	for target in _timers.keys():
		if not is_instance_valid(target):
			expired.append(target)
			continue

		_update_panel_position(_active_panels[target], target)
		_timers[target] -= delta
		if _timers[target] <= 0.0:
			expired.append(target)

	for target in expired:
		_remove_panel(target)


func _begin_scan() -> void:
	_scanning = true
	_clear_all_panels()

	var player := get_parent() as Node2D
	if player == null:
		return

	var player_pos := player.global_position
	_anim.play("scan")
	_scan_elements(player_pos)
	_scan_enemies(player_pos)


func _end_scan() -> void:
	_scanning = false
	_clear_all_panels()


func get_active_scan_targets() -> Array:
	return _active_panels.keys()


func _scan_elements(player_pos: Vector2) -> void:
	var results := _intersect_circle(player_pos, ELEMENT_SCAN_RADIUS, 2)
	for hit in results:
		var collider := hit.get("collider") as Node
		if collider == null:
			continue

		var pickup_node := _find_element_pickup(collider)
		if pickup_node == null or _active_panels.has(pickup_node):
			continue

		var element_id := _resolve_element_id(pickup_node)
		if element_id.is_empty():
			continue

		var data := ElementDatabase.get_element(element_id)
		if data.is_empty():
			continue

		_spawn_element_panel(pickup_node, data)
		_flash_element(pickup_node)


func _scan_enemies(player_pos: Vector2) -> void:
	var results := _intersect_circle(player_pos, ENEMY_SCAN_RADIUS, ENEMY_QUERY_MASK)
	for hit in results:
		var collider := hit.get("collider") as Node
		if collider == null:
			continue

		var enemy_node := _find_enemy_target(collider)
		if enemy_node == null or _active_panels.has(enemy_node):
			continue
		if player_pos.distance_to(enemy_node.global_position) > ENEMY_SCAN_RADIUS:
			continue
		if not enemy_node.has_method("get_scan_data"):
			continue

		var scan_data = enemy_node.get_scan_data()
		if not (scan_data is Dictionary):
			continue

		_spawn_enemy_panel(enemy_node, scan_data)
		_play_enemy_scan_sweep(enemy_node)


func _intersect_circle(origin: Vector2, radius: float, collision_mask: int) -> Array:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = radius
	query.shape = circle_shape
	query.transform = Transform2D(0.0, origin)
	query.collision_mask = collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return _space_state.intersect_shape(query, 64)


func _flash_element(node: Node2D) -> void:
	var tween := create_tween()
	var original := node.modulate
	node.modulate = Color(5, 5, 5, 1)
	tween.tween_property(node, "modulate", original, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_enemy_scan_sweep(enemy: Node2D) -> void:
	var canvas := _get_or_create_canvas()
	var target_rect := _get_target_screen_rect(enemy)
	var beam := ColorRect.new()
	beam.name = "EnemyScanBeam_" + enemy.name
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.color = Color(0.35, 0.95, 1.0, 0.28)
	beam.size = Vector2(14.0, target_rect.size.y + 24.0)
	beam.position = Vector2(target_rect.position.x - beam.size.x, target_rect.position.y - 12.0)
	canvas.add_child(beam)

	var tween := create_tween()
	tween.tween_property(beam, "position:x", target_rect.end.x + 8.0, ENEMY_SCAN_DURATION).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(beam, "modulate:a", 0.0, ENEMY_SCAN_DURATION).from(0.45)
	tween.tween_callback(beam.queue_free)


func _spawn_element_panel(pickup: Node2D, data: Dictionary) -> void:
	var panel := _build_element_panel(data)
	panel.name = "ScanOverlay_" + pickup.name
	_add_panel(pickup, panel, ELEMENT_PANEL_OFFSET)


func _spawn_enemy_panel(enemy: Node2D, scan_data: Dictionary) -> void:
	var panel := _build_enemy_panel(enemy, scan_data)
	panel.name = "ScanOverlay_" + enemy.name
	_add_panel(enemy, panel, ENEMY_PANEL_OFFSET)


func _add_panel(target: Node2D, panel: Control, offset: Vector2) -> void:
	var canvas := _get_or_create_canvas()
	canvas.add_child(panel)
	_panel_offsets[target] = offset
	_update_panel_position(panel, target)
	_active_panels[target] = panel
	_timers[target] = AUTO_DISMISS

	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT)


func _remove_panel(target: Node) -> void:
	if not _active_panels.has(target):
		return

	var panel := _active_panels[target] as Control
	if panel != null and is_instance_valid(panel):
		var tween := create_tween()
		tween.tween_property(panel, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
		tween.tween_callback(panel.queue_free)

	_active_panels.erase(target)
	_panel_offsets.erase(target)
	_timers.erase(target)


func _clear_all_panels() -> void:
	for target in _active_panels.keys():
		var panel := _active_panels[target] as Control
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
	_active_panels.clear()
	_panel_offsets.clear()
	_timers.clear()


func _update_panel_position(panel: Control, target: Node2D) -> void:
	var camera := get_viewport().get_camera_2d()
	var runtime := get_tree().root.get_node_or_null("MCPRuntime")
	if camera == null:
		if runtime:
			runtime.push_runtime_log("warn", "SCAN: Camera is NULL")
		return

	var offset: Vector2 = _panel_offsets.get(target, ELEMENT_PANEL_OFFSET)
	panel.position = _world_to_screen(target.global_position + offset)


func _build_element_panel(data: Dictionary) -> PanelContainer:
	var symbol := str(data.get(&"symbol", "?"))
	var display_name := str(data.get(&"display_name", "Unknown"))
	var category := str(data.get(&"category", "")).to_lower()
	var weight := float(data.get(&"weight", 0.0))

	var accent: Color = CATEGORY_COLOURS.get(category, FALLBACK_COLOUR)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ELEMENT_PANEL_WIDTH, ELEMENT_PANEL_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _build_panel_style(accent, 0.90))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)

	var badge := Label.new()
	badge.text = symbol
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(28, 28)
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", accent)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
	badge_style.corner_radius_top_left = 4
	badge_style.corner_radius_top_right = 4
	badge_style.corner_radius_bottom_left = 4
	badge_style.corner_radius_bottom_right = 4
	badge.add_theme_stylebox_override("normal", badge_style)
	header.add_child(badge)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	vbox.add_child(_build_separator(accent))

	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	vbox.add_child(details)

	var cat_label := Label.new()
	cat_label.text = category.capitalize()
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.85))
	cat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(cat_label)

	var wt_label := Label.new()
	wt_label.text = "%.1f kg" % weight
	wt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wt_label.add_theme_font_size_override("font_size", 10)
	wt_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70, 1.0))
	details.add_child(wt_label)

	return panel


func _build_enemy_panel(enemy: Node2D, scan_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ENEMY_PANEL_WIDTH, ENEMY_PANEL_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _build_panel_style(ENEMY_PANEL_ACCENT, 0.94))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "%s Scan" % _humanize_identifier(enemy.name)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 1.0))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Complex composition profile"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color(0.56, 0.88, 1.0, 0.92))
	vbox.add_child(subtitle)

	vbox.add_child(_build_separator(ENEMY_PANEL_ACCENT))
	vbox.add_child(_build_enemy_section("Composition", _format_composition(scan_data.get(&"composition", []))))
	vbox.add_child(_build_enemy_section("Weaknesses", _format_damage_tags(scan_data.get(&"weaknesses", []))))
	vbox.add_child(_build_enemy_section("Immunities", _format_damage_tags(scan_data.get(&"immunities", []))))

	return panel


func _build_enemy_section(title: String, body: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 1)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", Color(0.56, 0.88, 1.0, 0.92))
	section.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 10)
	body_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 1.0))
	section.add_child(body_label)

	return section


func _build_panel_style(accent: Color, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, alpha)
	style.border_color = accent
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 4
	return style


func _build_separator(accent: Color) -> HSeparator:
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(accent.r, accent.g, accent.b, 0.30)
	sep_style.content_margin_top = 0
	sep_style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_style)
	return sep


func _find_element_pickup(node: Node) -> Node2D:
	var cur: Node = node
	while cur != null:
		if cur.get_script() != null:
			var script = cur.get_script()
			if script != null and script.resource_path.ends_with("ElementPickup.gd"):
				return cur as Node2D
		cur = cur.get_parent()
	return null


func _find_enemy_target(node: Node) -> Node2D:
	var cur: Node = node
	while cur != null:
		if cur is Node2D and cur.is_in_group(&"enemy") and cur.has_method("get_scan_data"):
			return cur as Node2D
		cur = cur.get_parent()
	return null


func _resolve_element_id(pickup: Node) -> StringName:
	var element_id: StringName = pickup.get(&"element_id") if pickup.has_method("get") else &""
	if element_id.is_empty():
		element_id = pickup.get_meta(&"element_id", &"")
	return element_id


func _format_composition(composition: Variant) -> String:
	if not (composition is Array) or composition.is_empty():
		return "Unknown"

	var lines: PackedStringArray = []
	for entry in composition:
		if not (entry is Dictionary):
			continue

		var element_id := StringName(entry.get(&"element_id", &""))
		var pct := float(entry.get(&"pct", 0.0))
		if pct <= 1.0:
			pct *= 100.0

		var element_data := ElementDatabase.get_element(element_id)
		var display_name := str(element_data.get(&"display_name", _humanize_identifier(String(element_id))))
		var symbol := str(element_data.get(&"symbol", ""))
		var label := display_name if symbol.is_empty() else "%s %s" % [symbol, display_name]
		lines.append("%s %.0f%%" % [label, pct])

	return "\n".join(lines)


func _format_damage_tags(values: Variant) -> String:
	if not (values is Array) or values.is_empty():
		return "None"

	var tags: PackedStringArray = []
	for value in values:
		tags.append(_humanize_identifier(String(value)))
	return ", ".join(tags)


func _humanize_identifier(value: String) -> String:
	var words := value.replace("_", " ").split(" ", false)
	for index in range(words.size()):
		words[index] = words[index].capitalize()
	return " ".join(words)


func _get_or_create_canvas() -> CanvasLayer:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		current_scene = get_tree().root

	var existing := current_scene.get_node_or_null("ScannerCanvas")
	if existing != null:
		return existing as CanvasLayer

	var canvas := CanvasLayer.new()
	canvas.name = "ScannerCanvas"
	canvas.layer = 128
	current_scene.add_child(canvas)
	return canvas


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return world_pos
	return world_pos - camera.get_screen_center_position() + get_viewport().get_visible_rect().size * 0.5


func _get_target_screen_rect(target: Node2D) -> Rect2:
	var half_size := _estimate_target_half_size(target)
	var top_left := _world_to_screen(target.global_position - half_size)
	return Rect2(top_left, half_size * 2.0)


func _estimate_target_half_size(target: Node2D) -> Vector2:
	var scale_x := absf(target.global_scale.x)
	var scale_y := absf(target.global_scale.y)
	var shape_node := _find_collision_shape(target)
	if shape_node != null and shape_node.shape != null:
		if shape_node.shape is RectangleShape2D:
			return (shape_node.shape as RectangleShape2D).size * 0.5 * Vector2(scale_x, scale_y)
		if shape_node.shape is CircleShape2D:
			var radius := (shape_node.shape as CircleShape2D).radius
			return Vector2.ONE * radius * Vector2(scale_x, scale_y)
		if shape_node.shape is CapsuleShape2D:
			var capsule := shape_node.shape as CapsuleShape2D
			return Vector2(capsule.radius, capsule.height * 0.5) * Vector2(scale_x, scale_y)

	var sprite := _find_sprite(target)
	if sprite != null and sprite.texture != null:
		return sprite.texture.get_size() * 0.5 * Vector2(scale_x, scale_y)

	return Vector2(24.0, 32.0)


func _find_collision_shape(node: Node) -> CollisionShape2D:
	for child in node.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
		var nested := _find_collision_shape(child)
		if nested != null:
			return nested
	return null


func _find_sprite(node: Node) -> Sprite2D:
	for child in node.get_children():
		if child is Sprite2D:
			return child as Sprite2D
		var nested := _find_sprite(child)
		if nested != null:
			return nested
	return null
