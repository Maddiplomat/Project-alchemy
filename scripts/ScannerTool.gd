extends Node2D

## ScannerTool — attached to the Player node.
## Press and hold Q to reveal floating info panels for nearby pickups and enemies.

const ELEMENT_SCAN_RADIUS: float = 80.0
const ENEMY_SCAN_RADIUS: float = 120.0
const ELEMENT_AUTO_DISMISS: float = 3.0
const ENEMY_AUTO_DISMISS: float = 4.0
const ELEMENT_SCAN_DURATION: float = 0.4
const ENEMY_SCAN_DURATION: float = 1.2

## Visual tweak constants
const ELEMENT_PANEL_WIDTH: float = 140.0
const ELEMENT_PANEL_HEIGHT: float = 76.0
const ELEMENT_PANEL_OFFSET: Vector2 = Vector2(12.0, -64.0)
const ENEMY_PANEL_WIDTH: float = 220.0
const ENEMY_PANEL_HEIGHT: float = 126.0
const ENEMY_PANEL_OFFSET: Vector2 = Vector2(-110.0, -64.0)
const ENEMY_PANEL_ACCENT: Color = Color(0.36, 0.96, 1.0, 1.0)
const IMMUNITY_ACCENT: Color = Color(1.0, 0.35, 0.35, 1.0)

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
const DAMAGE_TYPE_COLOURS: Dictionary = {
	"oxidation": Color(1.00, 0.55, 0.15, 1.0),
	"electrical": Color(0.40, 0.95, 1.0, 1.0),
	"chemical": Color(0.42, 0.90, 0.35, 1.0),
	"radiation": Color(0.65, 1.00, 0.20, 1.0),
	"physical_blunt": Color(0.60, 0.46, 0.30, 1.0),
	"physical_sharp": Color(0.85, 0.88, 0.93, 1.0),
}
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
	_add_panel(pickup, panel, ELEMENT_PANEL_OFFSET, ELEMENT_AUTO_DISMISS)


func _spawn_enemy_panel(enemy: Node2D, scan_data: Dictionary) -> void:
	var panel := _build_enemy_panel(enemy, scan_data)
	panel.name = "ScanOverlay_" + enemy.name
	_add_panel(enemy, panel, ENEMY_PANEL_OFFSET, ENEMY_AUTO_DISMISS)


func _add_panel(target: Node2D, panel: Control, offset: Vector2, dismiss_after: float) -> void:
	var canvas := _get_or_create_canvas()
	canvas.add_child(panel)
	_panel_offsets[target] = offset
	_update_panel_position(panel, target)
	_active_panels[target] = panel
	_timers[target] = dismiss_after

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
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "%s Scan" % _humanize_identifier(enemy.name)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 1.0))
	vbox.add_child(title)

	vbox.add_child(_build_separator(ENEMY_PANEL_ACCENT))

	var composition_label := Label.new()
	composition_label.name = "CompositionLabel"
	composition_label.text = "Composition"
	composition_label.add_theme_font_size_override("font_size", 10)
	composition_label.add_theme_color_override("font_color", Color(0.56, 0.88, 1.0, 0.92))
	vbox.add_child(composition_label)

	var composition_bar := _build_composition_bar(scan_data.get(&"composition", []))
	composition_bar.name = "CompositionBar"
	vbox.add_child(composition_bar)

	var weakness_row := _build_tag_row(
		"Weaknesses",
		scan_data.get(&"weaknesses", []),
		false
	)
	weakness_row.name = "WeaknessesRow"
	vbox.add_child(weakness_row)

	var immunity_row := _build_tag_row(
		"Immunities",
		scan_data.get(&"immunities", []),
		true
	)
	immunity_row.name = "ImmunitiesRow"
	vbox.add_child(immunity_row)

	return panel


func _build_composition_bar(composition: Variant) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)

	var bar_frame := PanelContainer.new()
	bar_frame.custom_minimum_size = Vector2(0.0, 18.0)
	bar_frame.add_theme_stylebox_override("panel", _build_panel_style(Color(0.22, 0.28, 0.34, 1.0), 0.40))
	root.add_child(bar_frame)

	var bar := HBoxContainer.new()
	bar.name = "CompositionSegments"
	bar.add_theme_constant_override("separation", 0)
	bar_frame.add_child(bar)

	var legend := HBoxContainer.new()
	legend.name = "CompositionLegend"
	legend.add_theme_constant_override("separation", 6)
	root.add_child(legend)

	if not (composition is Array) or composition.is_empty():
		var unknown := Label.new()
		unknown.text = "Unknown"
		unknown.add_theme_font_size_override("font_size", 10)
		unknown.add_theme_color_override("font_color", Color(0.76, 0.82, 0.88, 1.0))
		legend.add_child(unknown)
		return root

	for entry in composition:
		if not (entry is Dictionary):
			continue

		var element_id := StringName(entry.get(&"element_id", &""))
		var pct := float(entry.get(&"pct", 0.0))
		var normalized_pct := clampf(pct if pct <= 1.0 else pct / 100.0, 0.0, 1.0)
		if is_zero_approx(normalized_pct):
			continue

		var element_data := ElementDatabase.get_element(element_id)
		var segment_color := _get_element_scan_colour(element_id, element_data)

		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(maxf(16.0, normalized_pct * 160.0), 14.0)
		segment.color = segment_color
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.tooltip_text = _format_composition_tooltip(element_id, normalized_pct, element_data)
		bar.add_child(segment)

		var legend_chip := ColorRect.new()
		legend_chip.custom_minimum_size = Vector2(8.0, 8.0)
		legend_chip.color = segment_color

		var legend_text := Label.new()
		legend_text.text = _get_element_scan_name(element_id, element_data)
		legend_text.add_theme_font_size_override("font_size", 9)
		legend_text.add_theme_color_override("font_color", Color(0.76, 0.82, 0.88, 1.0))

		var legend_item := HBoxContainer.new()
		legend_item.add_theme_constant_override("separation", 4)
		legend_item.add_child(legend_chip)
		legend_item.add_child(legend_text)
		legend.add_child(legend_item)

	return root


func _build_tag_row(title: String, values: Variant, is_immunity: bool) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override(
		"font_color",
		IMMUNITY_ACCENT if is_immunity else Color(0.56, 0.88, 1.0, 0.92)
	)
	row.add_child(title_label)

	var badges := HBoxContainer.new()
	badges.name = "Badges"
	badges.add_theme_constant_override("separation", 6)
	row.add_child(badges)

	if not (values is Array) or values.is_empty():
		var empty_label := Label.new()
		empty_label.text = "None"
		empty_label.add_theme_font_size_override("font_size", 10)
		empty_label.add_theme_color_override("font_color", Color(0.76, 0.82, 0.88, 0.85))
		badges.add_child(empty_label)
		return row

	for value in values:
		var damage_type := String(value)
		badges.add_child(_build_damage_badge(damage_type, is_immunity))

	return row


func _build_damage_badge(damage_type: String, is_immunity: bool) -> PanelContainer:
	var accent := IMMUNITY_ACCENT if is_immunity else _get_damage_type_colour(damage_type)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _build_badge_style(accent, is_immunity))

	var label := Label.new()
	label.text = _format_damage_badge_text(damage_type, is_immunity)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.97, 1.0) if is_immunity else Color(0.08, 0.10, 0.13, 1.0))
	badge.add_child(label)
	return badge


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


func _build_badge_style(accent: Color, is_immunity: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.24) if is_immunity else accent
	style.border_color = accent
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
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


func _humanize_identifier(value: String) -> String:
	var words := value.replace("_", " ").split(" ", false)
	for index in range(words.size()):
		words[index] = words[index].capitalize()
	return " ".join(words)


func _get_damage_type_colour(damage_type: String) -> Color:
	return DAMAGE_TYPE_COLOURS.get(damage_type, Color(0.72, 0.82, 0.94, 1.0))


func _get_element_scan_colour(element_id: StringName, element_data: Dictionary) -> Color:
	var category := str(element_data.get(&"category", "")).to_lower()
	if CATEGORY_COLOURS.has(category):
		return CATEGORY_COLOURS[category]
	if String(element_id) == "charcoal":
		return Color(0.30, 0.30, 0.34, 1.0)
	return FALLBACK_COLOUR


func _get_element_scan_name(element_id: StringName, element_data: Dictionary) -> String:
	var display_name := str(element_data.get(&"display_name", ""))
	if not display_name.is_empty():
		return display_name
	return _humanize_identifier(String(element_id))


func _format_composition_tooltip(element_id: StringName, pct: float, element_data: Dictionary) -> String:
	return "%s %.0f%%" % [_get_element_scan_name(element_id, element_data), pct * 100.0]


func _format_damage_badge_text(damage_type: String, is_immunity: bool) -> String:
	var label := _humanize_identifier(damage_type)
	if is_immunity:
		return "⊘ %s" % label
	return label


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
