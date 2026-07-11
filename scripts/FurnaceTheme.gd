class_name FurnaceTheme
extends RefCounted


static func apply(panel: PanelContainer, slot_refs: Dictionary, temperature_gauge: ProgressBar, buttons: Dictionary, labels: Dictionary, colors: Dictionary) -> void:
	if panel == null or temperature_gauge == null:
		return

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = colors.get("panel_bg", Color(0.10, 0.11, 0.13, 0.96))
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = colors.get("panel_border", Color(0.28, 0.30, 0.34, 1.0))
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel.add_theme_stylebox_override("panel", panel_style)

	for slot_id: StringName in slot_refs:
		var slot_panel: PanelContainer = slot_refs[slot_id].get(&"panel")
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = colors.get("slot_bg", Color(0.14, 0.16, 0.19, 1.0))
		slot_style.border_width_left = 1
		slot_style.border_width_top = 1
		slot_style.border_width_right = 1
		slot_style.border_width_bottom = 1
		slot_style.border_color = colors.get("slot_border", Color(0.34, 0.37, 0.41, 1.0))
		slot_style.corner_radius_top_left = 10
		slot_style.corner_radius_top_right = 10
		slot_style.corner_radius_bottom_right = 10
		slot_style.corner_radius_bottom_left = 10
		slot_panel.add_theme_stylebox_override("panel", slot_style)

		var slot_visual: Panel = slot_refs[slot_id].get(&"visual")
		var visual_style := StyleBoxFlat.new()
		visual_style.bg_color = Color(0.09, 0.10, 0.12, 1.0)
		visual_style.border_width_left = 1
		visual_style.border_width_top = 1
		visual_style.border_width_right = 1
		visual_style.border_width_bottom = 1
		visual_style.border_color = Color(0.23, 0.25, 0.29, 1.0)
		visual_style.corner_radius_top_left = 8
		visual_style.corner_radius_top_right = 8
		visual_style.corner_radius_bottom_right = 8
		visual_style.corner_radius_bottom_left = 8
		slot_visual.add_theme_stylebox_override("panel", visual_style)

	var gauge_background := StyleBoxFlat.new()
	gauge_background.bg_color = Color(0.08, 0.09, 0.11, 1.0)
	gauge_background.border_width_left = 1
	gauge_background.border_width_top = 1
	gauge_background.border_width_right = 1
	gauge_background.border_width_bottom = 1
	gauge_background.border_color = colors.get("slot_border", Color(0.34, 0.37, 0.41, 1.0))
	gauge_background.corner_radius_top_left = 8
	gauge_background.corner_radius_top_right = 8
	gauge_background.corner_radius_bottom_right = 8
	gauge_background.corner_radius_bottom_left = 8
	temperature_gauge.add_theme_stylebox_override("background", gauge_background)

	var gauge_fill := StyleBoxFlat.new()
	gauge_fill.bg_color = colors.get("gauge_normal", Color(0.95, 0.62, 0.22, 1.0))
	gauge_fill.corner_radius_top_left = 6
	gauge_fill.corner_radius_top_right = 6
	gauge_fill.corner_radius_bottom_right = 6
	gauge_fill.corner_radius_bottom_left = 6
	temperature_gauge.add_theme_stylebox_override("fill", gauge_fill)
	temperature_gauge.add_theme_color_override("font_color", Color(0, 0, 0, 0))

	style_button(buttons.get("smelt"), colors.get("smelt_button", Color(0.79, 0.47, 0.18, 1.0)))
	style_button(buttons.get("forge"), colors.get("forge_button", Color(0.39, 0.54, 0.74, 1.0)))
	style_button(buttons.get("recipe_cycle"), colors.get("button_idle", Color(0.28, 0.30, 0.35, 1.0)))
	style_button(buttons.get("fire_toggle"), colors.get("button_idle", Color(0.28, 0.30, 0.35, 1.0)))
	style_button(buttons.get("close"), colors.get("button_idle", Color(0.28, 0.30, 0.35, 1.0)))

	var title_label: Label = labels.get("title")
	if title_label != null:
		title_label.add_theme_color_override("font_color", Color(0.94, 0.95, 0.97, 1.0))
	var summary_label: Label = labels.get("summary")
	if summary_label != null:
		summary_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.79, 1.0))
	var temp_label: Label = labels.get("temp")
	if temp_label != null:
		temp_label.add_theme_color_override("font_color", colors.get("gauge_normal", Color(0.95, 0.62, 0.22, 1.0)))
	var action_hint_label: Label = labels.get("action_hint")
	if action_hint_label != null:
		action_hint_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.79, 1.0))
	var fuel_cost_label: Label = labels.get("fuel_cost")
	if fuel_cost_label != null:
		fuel_cost_label.add_theme_color_override("font_color", Color(0.60, 0.76, 0.67, 1.0))
	var mode_label: Label = labels.get("mode")
	if mode_label != null:
		mode_label.add_theme_color_override("font_color", Color(0.93, 0.94, 0.96, 1.0))
	var ratio_value_label: Label = labels.get("ratio_value")
	if ratio_value_label != null:
		ratio_value_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.79, 1.0))
	var danger_label: Label = labels.get("danger")
	if danger_label != null:
		danger_label.add_theme_color_override("font_color", colors.get("gauge_danger", Color(0.89, 0.29, 0.24, 1.0)))


static func style_button(button: Button, accent_color: Color) -> void:
	if button == null:
		return

	var normal := StyleBoxFlat.new()
	normal.bg_color = accent_color
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_right = 8
	normal.corner_radius_bottom_left = 8
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = accent_color.darkened(0.3)

	var hover := normal.duplicate()
	hover.bg_color = accent_color.lightened(0.12)

	var pressed := normal.duplicate()
	pressed.bg_color = accent_color.darkened(0.16)

	var disabled := normal.duplicate()
	disabled.bg_color = accent_color.darkened(0.45)
	disabled.border_color = accent_color.darkened(0.55)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.68, 0.68, 0.70, 1.0))
