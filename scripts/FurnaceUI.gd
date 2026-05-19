extends CanvasLayer

signal ui_closed
signal smelt_requested

const MAX_TEMPERATURE := 2000.0
const DANGER_TEMPERATURE := 1600.0
const CARBONISATION_OPTIMAL_MIN := 400.0
const CARBONISATION_OPTIMAL_MAX := 700.0
const CARBON_RATIO_MIN := 0.0
const CARBON_RATIO_MAX := 10.0
const PANEL_BG_COLOR := Color(0.10, 0.11, 0.13, 0.96)
const PANEL_BORDER_COLOR := Color(0.28, 0.30, 0.34, 1.0)
const SLOT_BG_COLOR := Color(0.14, 0.16, 0.19, 1.0)
const SLOT_BORDER_COLOR := Color(0.34, 0.37, 0.41, 1.0)
const SLOT_EMPTY_COLOR := Color(0.52, 0.55, 0.60, 1.0)
const GAUGE_NORMAL_COLOR := Color(0.95, 0.62, 0.22, 1.0)
const GAUGE_DANGER_COLOR := Color(0.89, 0.29, 0.24, 1.0)
const CARBONISATION_GOOD_COLOR := Color(0.34, 0.82, 0.45, 1.0)
const CARBONISATION_SLAG_COLOR := Color(0.89, 0.29, 0.24, 1.0)
const BUTTON_IDLE_COLOR := Color(0.28, 0.30, 0.35, 1.0)
const BUTTON_HOVER_COLOR := Color(0.36, 0.39, 0.45, 1.0)
const BUTTON_PRESSED_COLOR := Color(0.22, 0.24, 0.28, 1.0)
const SMELT_BUTTON_COLOR := Color(0.79, 0.47, 0.18, 1.0)
const PANEL_VIEW_SCALE := 0.46
const PANEL_MARGIN := Vector2(24.0, 24.0)
const RATIO_GUIDE_BG_COLOR := Color(0.18, 0.20, 0.23, 0.82)
const RATIO_IRON_FILL_COLOR := Color(0.34, 0.44, 0.52, 0.92)
const RATIO_CARBON_FILL_COLOR := Color(0.54, 0.31, 0.12, 0.96)
const RATIO_GUIDE_TARGET_COLOR := Color(0.34, 0.82, 0.45, 0.32)
const RATIO_GUIDE_MARKER_COLOR := Color(0.97, 0.97, 0.97, 0.95)
const RATIO_GUIDE_TOOLTIP_FALLBACK := "Load a carbon source into Input B for steel guidance."
const OUTPUT_PREVIEW_COLOR := Color(0.58, 0.61, 0.66, 1.0)
const FURNACE_EXPLOSION_RADIUS := 32.0
const FURNACE_EXPLOSION_DAMAGE := 35
const FURNACE_EXPLOSION_SHAKE_STRENGTH := 1.2
const FURNACE_EXPLOSION_SHAKE_DURATION := 0.6
const FURNACE_EXPLOSION_SPARK_COUNT := 80
const FURNACE_EXPLOSION_SPARK_LIFETIME := 0.4
const FURNACE_EXPLOSION_SLOT_LOSS_CHANCE := 0.5

@onready var root: Control = $Root
@onready var panel: PanelContainer = $Root/PanelContainer
@onready var title_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var summary_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/SummaryLabel
@onready var close_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/CloseButton
@onready var smelt_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/SmeltButton
@onready var action_hint_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/ActionHintLabel
@onready var mode_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/ActionLabel
@onready var temperature_column_box: VBoxContainer = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer
@onready var gauge_frame: Control = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/GaugeFrame
@onready var temp_readout_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/TemperatureReadout
@onready var danger_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/DangerLabel
@onready var danger_zone: ColorRect = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/GaugeFrame/DangerZone
@onready var danger_line: ColorRect = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/GaugeFrame/DangerLine
@onready var temperature_gauge: ProgressBar = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/GaugeFrame/TemperatureGauge

var _is_open := false
var _is_initialized := false
var _bound_furnace: Node
var carbonisation_mode := false
var _last_reaction_result: Dictionary = {}
var _placeholder_textures := {}
var ratio_container: VBoxContainer
var ratio_slider: HSlider
var ratio_value_label: Label
var ratio_graph_frame: Control
var ratio_graph_background: ColorRect
var ratio_iron_fill: ColorRect
var ratio_carbon_fill: ColorRect
var ratio_target_zone: ColorRect
var ratio_current_marker: ColorRect
var carbon_slag_zone: ColorRect
var carbon_optimal_zone: ColorRect
var _explosion_spark_texture: Texture2D
var _slot_refs: Dictionary[StringName, Dictionary] = {}
var _slot_state: Dictionary[StringName, Dictionary] = {
	&"input_a": {&"item_id": &"", &"quantity": 0},
	&"input_b": {&"item_id": &"", &"quantity": 0},
	&"fuel": {&"item_id": &"", &"quantity": 0},
	&"output": {&"item_id": &"", &"quantity": 0},
}


func _ready() -> void:
	_ensure_dynamic_ui_nodes()
	close_button.pressed.connect(_on_close_pressed)
	smelt_button.pressed.connect(_on_smelt_pressed)
	ratio_slider.value_changed.connect(_on_ratio_slider_changed)
	get_viewport().size_changed.connect(_layout_panel)

	_slot_refs = {
		&"input_a": _build_slot_ref("InputSlotA"),
		&"input_b": _build_slot_ref("InputSlotB"),
		&"fuel": _build_slot_ref("FuelSlot"),
		&"output": _build_slot_ref("OutputSlot"),
	}

	_apply_theme()
	_reset_slots()
	_update_ratio_label(ratio_slider.value)
	_update_ratio_guidance()
	_update_mode_state(false)
	_update_temperature_display(0.0)
	_layout_panel()
	root.visible = false
	_is_initialized = true

	if is_instance_valid(_bound_furnace):
		call_deferred("_pull_state_from_furnace")


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("interact"):
		close_ui()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_ui()
		get_viewport().set_input_as_handled()


func open_ui() -> void:
	_is_open = true
	_update_mode_state(_should_use_carbonisation_mode())
	_layout_panel()
	root.visible = true
	close_button.grab_focus()


func close_ui() -> void:
	if not _is_open:
		return
	_is_open = false
	root.visible = false
	ui_closed.emit()


func is_open() -> bool:
	return _is_open


func _layout_panel() -> void:
	if panel == null:
		return

	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.pivot_offset = Vector2.ZERO
	panel.size = panel.custom_minimum_size
	panel.scale = Vector2(PANEL_VIEW_SCALE, PANEL_VIEW_SCALE)

	var viewport_size := get_viewport().get_visible_rect().size
	var scaled_size := panel.custom_minimum_size * PANEL_VIEW_SCALE
	panel.position = Vector2(
		PANEL_MARGIN.x,
		maxf(PANEL_MARGIN.y, (viewport_size.y - scaled_size.y) * 0.5)
	)


func bind_furnace(furnace: Node) -> void:
	var callback := Callable(self, "_on_furnace_temp_changed")
	if is_instance_valid(_bound_furnace) and _bound_furnace.is_connected("temp_changed", callback):
		_bound_furnace.disconnect("temp_changed", callback)

	_bound_furnace = furnace

	if is_instance_valid(_bound_furnace) and _bound_furnace.has_signal("temp_changed"):
		if not _bound_furnace.is_connected("temp_changed", callback):
			_bound_furnace.connect("temp_changed", callback)

	if _is_initialized:
		call_deferred("_pull_state_from_furnace")


func can_accept_inventory_drop(global_mouse_position: Vector2, item_id: StringName, qty: int) -> bool:
	if not _is_open or not _is_initialized or not is_instance_valid(_bound_furnace):
		return false

	var slot_id := _get_drop_slot_id(global_mouse_position)
	if slot_id.is_empty():
		return false

	return _can_accept_drop_to_slot(slot_id, item_id, qty)


func handle_inventory_drop(global_mouse_position: Vector2, item_id: StringName, qty: int) -> bool:
	if not can_accept_inventory_drop(global_mouse_position, item_id, qty):
		return false

	var slot_id := _get_drop_slot_id(global_mouse_position)
	if slot_id.is_empty():
		return false

	if not _bound_furnace.has_method("set_input"):
		return false

	var accepted = _bound_furnace.set_input(slot_id, item_id, qty)
	if accepted:
		_pull_state_from_furnace()
	return accepted


func set_input_slot_a(item_id: StringName, quantity: int) -> void:
	_set_slot(&"input_a", item_id, quantity, "No material")


func set_input_slot_b(item_id: StringName, quantity: int) -> void:
	_set_slot(&"input_b", item_id, quantity, "No material")


func set_fuel_slot(item_id: StringName, quantity: int) -> void:
	_set_slot(&"fuel", item_id, quantity, "Fuel item")


func set_probable_output(item_id: StringName, quantity: int) -> void:
	_set_slot(&"output", item_id, quantity, "Awaiting recipe")


func show_output_placeholder(text: String) -> void:
	_slot_state[&"output"] = {&"item_id": &"", &"quantity": 0}
	_apply_slot_visual(&"output", &"", 0, text)
	_update_smelt_button_state()


func _on_close_pressed() -> void:
	close_ui()


func _on_smelt_pressed() -> void:
	_evaluate_smelt_request()
	smelt_requested.emit()


func _on_ratio_slider_changed(value: float) -> void:
	_update_ratio_label(value)
	_update_ratio_guidance()
	_refresh_probable_output()


func _on_furnace_temp_changed(current_temp: float) -> void:
	if not _is_initialized:
		return
	_update_temperature_display(current_temp)
	_pull_state_from_furnace()


func _build_slot_ref(node_name: String) -> Dictionary:
	var panel_path := "Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/%s" % node_name
	var slot_path := "%s/MarginContainer/VBoxContainer" % panel_path
	return {
		&"panel": get_node(NodePath(panel_path)),
		&"visual": get_node(NodePath("%s/IconHolder/SlotVisual" % slot_path)),
		&"icon": get_node(NodePath("%s/IconHolder/SlotVisual/ItemIcon" % slot_path)),
		&"quantity": get_node(NodePath("%s/IconHolder/SlotVisual/QuantityLabel" % slot_path)),
		&"name": get_node(NodePath("%s/ItemNameLabel" % slot_path)),
	}


func _apply_theme() -> void:
	if not _is_initialized and temperature_gauge == null:
		return

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG_COLOR
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = PANEL_BORDER_COLOR
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel.add_theme_stylebox_override("panel", panel_style)

	for slot_id: StringName in _slot_refs:
		var slot_panel: PanelContainer = _slot_refs[slot_id][&"panel"]
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = SLOT_BG_COLOR
		slot_style.border_width_left = 1
		slot_style.border_width_top = 1
		slot_style.border_width_right = 1
		slot_style.border_width_bottom = 1
		slot_style.border_color = SLOT_BORDER_COLOR
		slot_style.corner_radius_top_left = 10
		slot_style.corner_radius_top_right = 10
		slot_style.corner_radius_bottom_right = 10
		slot_style.corner_radius_bottom_left = 10
		slot_panel.add_theme_stylebox_override("panel", slot_style)

		var slot_visual: Panel = _slot_refs[slot_id][&"visual"]
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
	gauge_background.border_color = SLOT_BORDER_COLOR
	gauge_background.corner_radius_top_left = 8
	gauge_background.corner_radius_top_right = 8
	gauge_background.corner_radius_bottom_right = 8
	gauge_background.corner_radius_bottom_left = 8
	temperature_gauge.add_theme_stylebox_override("background", gauge_background)

	var gauge_fill := StyleBoxFlat.new()
	gauge_fill.bg_color = GAUGE_NORMAL_COLOR
	gauge_fill.corner_radius_top_left = 6
	gauge_fill.corner_radius_top_right = 6
	gauge_fill.corner_radius_bottom_right = 6
	gauge_fill.corner_radius_bottom_left = 6
	temperature_gauge.add_theme_stylebox_override("fill", gauge_fill)
	temperature_gauge.add_theme_color_override("font_color", Color(0, 0, 0, 0))

	_style_button(smelt_button, SMELT_BUTTON_COLOR)
	_style_button(close_button, BUTTON_IDLE_COLOR)
	title_label.add_theme_color_override("font_color", Color(0.94, 0.95, 0.97, 1.0))
	summary_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.79, 1.0))
	temp_readout_label.add_theme_color_override("font_color", GAUGE_NORMAL_COLOR)
	action_hint_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.79, 1.0))
	mode_label.add_theme_color_override("font_color", Color(0.93, 0.94, 0.96, 1.0))
	ratio_value_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.79, 1.0))
	danger_label.add_theme_color_override("font_color", GAUGE_DANGER_COLOR)


func _style_button(button: Button, accent_color: Color) -> void:
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


func _reset_slots() -> void:
	if not _is_initialized and _slot_refs.is_empty():
		return

	_apply_slot_visual(&"input_a", &"", 0, "No material")
	_apply_slot_visual(&"input_b", &"", 0, "No material")
	_apply_slot_visual(&"fuel", &"", 0, "Fuel item")
	_apply_slot_visual(&"output", &"", 0, "Awaiting recipe")
	_update_mode_state(false)
	_update_smelt_button_state()


func _pull_state_from_furnace() -> void:
	if not _is_initialized:
		return

	if not is_instance_valid(_bound_furnace):
		set_fuel_slot(&"", 0)
		return

	var temp_value = _bound_furnace.get("current_temp")
	if temp_value != null:
		_update_temperature_display(float(temp_value))

	if _bound_furnace.has_method("get_input"):
		var input_a: Dictionary = _bound_furnace.get_input(&"input_a")
		var input_b: Dictionary = _bound_furnace.get_input(&"input_b")
		_set_slot(&"input_a", input_a.get(&"item_id", &""), int(input_a.get(&"quantity", 0)), "No material")
		_set_slot(&"input_b", input_b.get(&"item_id", &""), int(input_b.get(&"quantity", 0)), "No material")

	if not _bound_furnace.has_method("get_fuel_state"):
		return

	var fuel_state: Dictionary = _bound_furnace.get_fuel_state()
	set_fuel_slot(
		fuel_state.get(&"item_id", &""),
		int(fuel_state.get(&"quantity", 0))
	)
	_update_mode_state(_should_use_carbonisation_mode())


func _set_slot(slot_id: StringName, item_id: StringName, quantity: int, empty_label: String) -> void:
	if not _is_initialized:
		return

	var clamped_quantity := maxi(quantity, 0)
	_slot_state[slot_id] = {
		&"item_id": item_id if clamped_quantity > 0 else &"",
		&"quantity": clamped_quantity,
	}
	_apply_slot_visual(slot_id, item_id, clamped_quantity, empty_label)
	if slot_id == &"input_b":
		_update_ratio_label(ratio_slider.value)
		_update_ratio_guidance()
	if slot_id != &"output":
		_refresh_probable_output()
	_update_smelt_button_state()


func _apply_slot_visual(slot_id: StringName, item_id: StringName, quantity: int, empty_label: String) -> void:
	var refs: Dictionary = _slot_refs.get(slot_id, {})
	if refs.is_empty():
		return

	var icon: TextureRect = refs[&"icon"]
	var quantity_label: Label = refs[&"quantity"]
	var name_label: Label = refs[&"name"]
	var has_item := not item_id.is_empty() and quantity > 0

	icon.texture = _get_placeholder_texture(String(item_id)) if has_item else null
	icon.modulate = _get_item_color(String(item_id)) if has_item else SLOT_EMPTY_COLOR
	quantity_label.text = "x%d" % quantity if has_item else ""
	name_label.text = _get_item_label(item_id) if has_item else empty_label
	name_label.modulate = Color(0.93, 0.94, 0.96, 1.0) if has_item else Color(0.57, 0.60, 0.65, 1.0)


func _refresh_probable_output() -> void:
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})

	var input_a_id: StringName = input_a.get(&"item_id", &"")
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	_update_mode_state(_should_use_carbonisation_mode())

	if input_a_qty <= 0 and input_b_qty <= 0:
		show_output_placeholder("Awaiting recipe")
		return

	if input_b_qty <= 0 and input_a_id == &"wood":
		var output_id := _get_charred_output_id()
		_slot_state[&"output"] = {&"item_id": output_id, &"quantity": maxi(1, input_a_qty)}
		_apply_slot_visual(&"output", output_id, maxi(1, input_a_qty), "Awaiting recipe")
		return

	if input_a_qty <= 0 and input_b_id == &"wood":
		var output_id := _get_charred_output_id()
		_slot_state[&"output"] = {&"item_id": output_id, &"quantity": maxi(1, input_b_qty)}
		_apply_slot_visual(&"output", output_id, maxi(1, input_b_qty), "Awaiting recipe")
		return

	if carbonisation_mode:
		show_output_placeholder("Awaiting heat")
		return

	if input_a_qty <= 0 or input_b_qty <= 0:
		show_output_placeholder("Load two materials")
		return

	var prediction := _evaluate_alloy_prediction(input_a_id, input_b_id, _get_current_temperature())
	_show_output_prediction(prediction)


func _update_smelt_button_state() -> void:
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	smelt_button.disabled = input_a_qty <= 0 if carbonisation_mode else (input_a_qty <= 0 or input_b_qty <= 0)


func _get_charred_output_id() -> StringName:
	if ElementDatabase.has_element(&"charcoal"):
		return &"charcoal"
	return &"pure_carbon"


func _update_temperature_display(current_temp: float) -> void:
	if temperature_gauge == null or temp_readout_label == null or danger_label == null:
		return

	var clamped_temp := clampf(current_temp, 0.0, MAX_TEMPERATURE)
	temperature_gauge.value = clamped_temp
	temp_readout_label.text = "%d°C" % int(round(clamped_temp))

	var fill_style: StyleBoxFlat = temperature_gauge.get_theme_stylebox("fill").duplicate()
	if carbonisation_mode:
		var is_slag := clamped_temp > CARBONISATION_OPTIMAL_MAX
		var is_optimal := clamped_temp >= CARBONISATION_OPTIMAL_MIN and clamped_temp <= CARBONISATION_OPTIMAL_MAX
		var fill_color := GAUGE_NORMAL_COLOR
		if is_slag:
			fill_color = CARBONISATION_SLAG_COLOR
		elif is_optimal:
			fill_color = CARBONISATION_GOOD_COLOR
		fill_style.bg_color = fill_color
		temp_readout_label.add_theme_color_override("font_color", fill_color)
		danger_label.text = "400-700°C makes Charcoal | >700°C overheats the furnace"
		danger_label.visible = true
	else:
		var is_danger := clamped_temp >= DANGER_TEMPERATURE
		fill_style.bg_color = GAUGE_DANGER_COLOR if is_danger else GAUGE_NORMAL_COLOR
		temp_readout_label.add_theme_color_override("font_color", GAUGE_DANGER_COLOR if is_danger else GAUGE_NORMAL_COLOR)
		danger_label.text = "Danger above 1600°C"
		danger_label.visible = is_danger

	temperature_gauge.add_theme_stylebox_override("fill", fill_style)


func _get_drop_slot_id(global_mouse_position: Vector2) -> StringName:
	for slot_id: StringName in [&"input_a", &"input_b", &"fuel"]:
		var slot_ref: Dictionary = _slot_refs.get(slot_id, {})
		if slot_ref.is_empty():
			continue

		var slot_visual: Control = slot_ref.get(&"visual")
		if slot_visual != null:
			var local_pos := slot_visual.make_canvas_position_local(global_mouse_position)
			if Rect2(Vector2.ZERO, slot_visual.size).has_point(local_pos):
				return slot_id

	return &""


func _can_accept_drop_to_slot(slot_id: StringName, item_id: StringName, qty: int) -> bool:
	if qty <= 0 or item_id.is_empty():
		return false
	if slot_id == &"fuel":
		var fuel_state: Dictionary = _slot_state.get(slot_id, {})
		var current_fuel_id: StringName = fuel_state.get(&"item_id", &"")
		return ChemistryEngine.get_fuel_value(String(item_id)) > 0.0 and (
			current_fuel_id.is_empty() or current_fuel_id == item_id
		)
	if ElementDatabase.get_element(item_id).is_empty():
		return false

	var slot_state: Dictionary = _slot_state.get(slot_id, {})
	var current_item_id: StringName = slot_state.get(&"item_id", &"")
	return current_item_id.is_empty() or current_item_id == item_id


func _get_item_label(item_id: StringName) -> String:
	if item_id.is_empty():
		return ""

	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", item_id))

	return String(item_id).replace("_", " ").capitalize()


func _get_item_color(item_id: String) -> Color:
	match item_id:
		"wood":
			return Color.BURLYWOOD
		"stone":
			return Color.GRAY
		"iron":
			return Color.SILVER
		"pure_carbon":
			return Color(0.29, 0.31, 0.35, 1.0)
		"charcoal":
			return Color(0.18, 0.19, 0.21, 1.0)
		"slag":
			return Color(0.43, 0.18, 0.16, 1.0)
		"primitive_axe":
			return Color(0.76, 0.82, 0.88, 1.0)
		_:
			return Color.WHITE


func _get_placeholder_texture(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null

	if _placeholder_textures.has(item_id):
		return _placeholder_textures[item_id]

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.WHITE)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 96
	texture.height = 96
	_placeholder_textures[item_id] = texture
	return texture


func _evaluate_smelt_request() -> void:
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	var input_a_id: StringName = input_a.get(&"item_id", &"")
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	var current_temp := 0.0
	if is_instance_valid(_bound_furnace):
		current_temp = float(_bound_furnace.get("current_temp"))

	_update_mode_state(input_b_qty <= 0)

	# ── CARBONISATION PATH ───────────────────────────────────────────────────
	if carbonisation_mode:
		if input_a_qty <= 0 or input_a_id != &"wood":
			show_output_placeholder("Load Wood into Input A")
			action_hint_label.text = "Carbonisation mode needs Wood in Input A."
			return

		# Validate temperature range 400–700°C
		if current_temp < CARBONISATION_OPTIMAL_MIN:
			show_output_placeholder("Heat too low")
			action_hint_label.text = "Need 400–700°C for charcoal."
			return

		if current_temp > CARBONISATION_OPTIMAL_MAX:
			var carbonisation_explosion := _build_explosion_result(
				"Temperature exceeded 700°C during carbonisation. Furnace overheated."
			)
			_last_reaction_result = carbonisation_explosion
			var carbonisation_inputs_log := [{"item_id": input_a_id, "quantity": input_a_qty}]
			_consume_furnace_slot(&"input_a", input_a_id, input_a_qty)
			_apply_reaction_result(carbonisation_explosion, 0, carbonisation_inputs_log, current_temp)
			return

		var carb_result := ChemistryEngine.evaluate_reaction("wood", null, 0.0, current_temp)
		_last_reaction_result = carb_result

		# Consume Wood from Slot A
		var consumed_a := _consume_furnace_slot(&"input_a", input_a_id, input_a_qty)
		var inputs_log := [{"item_id": input_a_id, "quantity": consumed_a}]

		_apply_reaction_result(carb_result, consumed_a, inputs_log, current_temp)
		return

	# ── SMELTING PATH ────────────────────────────────────────────────────────
	if input_a_qty <= 0 or input_b_qty <= 0:
		show_output_placeholder("Load two materials")
		action_hint_label.text = "Smelting mode needs both input slots filled."
		return

	# Temperature >1600°C → explosion regardless of inputs
	if current_temp > DANGER_TEMPERATURE:
		var explosion_result := _build_explosion_result(
			"Temperature exceeded 1600°C during smelting. Furnace overheated."
		)
		_last_reaction_result = explosion_result
		var inputs_log := [
			{"item_id": input_a_id, "quantity": input_a_qty},
			{"item_id": input_b_id, "quantity": input_b_qty},
		]
		_consume_furnace_slot(&"input_a", input_a_id, input_a_qty)
		_consume_furnace_slot(&"input_b", input_b_id, input_b_qty)
		_apply_reaction_result(explosion_result, 0, inputs_log, current_temp)
		return

	# Normal smelting: validate 1200–1600°C
	if current_temp < 1200.0:
		show_output_placeholder("Heat too low for smelting")
		action_hint_label.text = "Smelting requires 1200–1600°C."
		return

	var source_info := _get_active_carbon_source_info()
	var alloy_result := ChemistryEngine.evaluate_reaction(
		String(input_a_id),
		String(input_b_id),
		_get_effective_b_ratio_from_slider(source_info),
		current_temp
	)
	_last_reaction_result = alloy_result

	# Consume both inputs from furnace
	var qty_used := mini(input_a_qty, input_b_qty)
	var consumed_a2 := _consume_furnace_slot(&"input_a", input_a_id, qty_used)
	var consumed_b2 := _consume_furnace_slot(&"input_b", input_b_id, qty_used)
	var inputs_log2 := [
		{"item_id": input_a_id, "quantity": consumed_a2},
		{"item_id": input_b_id, "quantity": consumed_b2},
	]
	_apply_reaction_result(alloy_result, qty_used, inputs_log2, current_temp)


## Consume `qty` of `item_id` from a furnace input slot and mirror to InventoryManager.
## Returns the actual quantity consumed.
func _consume_furnace_slot(slot_id: StringName, item_id: StringName, qty: int) -> int:
	if qty <= 0 or item_id.is_empty():
		return 0

	var actual_qty := qty

	# Update furnace internal state
	if is_instance_valid(_bound_furnace) and _bound_furnace.has_method("clear_input"):
		_bound_furnace.clear_input(slot_id)
	elif is_instance_valid(_bound_furnace):
		# Fallback: zero out the slot directly if clear_input is unavailable
		if _bound_furnace._input_slots.has(slot_id):
			_bound_furnace._input_slots[slot_id] = {&"item_id": &"", &"quantity": 0}

	# Remove from player inventory
	if InventoryManager.has_item(item_id):
		InventoryManager.remove_item(item_id, actual_qty)

	# Clear the local slot state
	_slot_state[slot_id] = {&"item_id": &"", &"quantity": 0}
	_apply_slot_visual(slot_id, &"", 0, "No material")
	return actual_qty


## Apply a reaction result: update the output slot, deliver to InventoryManager,
## log to DiscoveryLog, and handle the explosion special case.
func _apply_reaction_result(
		result: Dictionary,
		quantity: int,
		inputs_log: Array,
		temp: float) -> void:
	var output_id := StringName(str(result.get("output_id", "")))
	var notes := str(result.get("notes", ""))
	var tier := str(result.get("tier", "unknown"))

	action_hint_label.text = notes if not notes.is_empty() else "Reaction evaluated."

	# ── EXPLOSION ────────────────────────────────────────────────────────────
	if output_id == &"explosion":
		_trigger_explosion(notes, inputs_log, temp)
		return

	# ── NO REACTION / FAILED TEMP CHECK ─────────────────────────────────────
	if output_id.is_empty():
		show_output_placeholder(notes if not notes.is_empty() else "No reaction")
		_log_to_discovery(result, inputs_log, temp)
		return

	# ── SUCCESSFUL REACTION ──────────────────────────────────────────────────
	var output_quantity := maxi(quantity, 1)

	# Deliver output to InventoryManager
	_deliver_output_to_inventory(output_id, output_quantity)

	# Update UI output slot
	_slot_state[&"output"] = {&"item_id": output_id, &"quantity": output_quantity}
	_apply_slot_visual(&"output", output_id, output_quantity, "Awaiting recipe")
	_update_smelt_button_state()

	# Log to DiscoveryLog (emits signal, marks first discovery, etc.)
	_log_to_discovery(result, inputs_log, temp)

	# Tier-specific feedback
	_show_tier_feedback(output_id, tier)


## Deliver the smelted output to the player's InventoryManager.
func _deliver_output_to_inventory(output_id: StringName, quantity: int) -> void:
	if output_id.is_empty() or quantity <= 0:
		return

	var element_data := ElementDatabase.get_element(output_id)
	if element_data.is_empty():
		# Build a minimal item entry for products not yet in the database.
		element_data = {
			&"id": output_id,
			&"display_name": String(output_id).replace("_", " ").capitalize(),
			&"weight": 1.0,
			&"purity": 1.0,
		}

	var item_data := element_data.duplicate(true)
	item_data[&"id"] = output_id
	item_data[&"purity"] = 1.0
	item_data[&"category"] = InventoryManager.InventoryItemCategory.ELEMENT

	var added := InventoryManager.add_item(item_data, quantity)
	if not added:
		action_hint_label.text = "Inventory full! Output dropped on the floor."
		print("[FurnaceUI] Could not add %s x%d to inventory — capacity reached." % [output_id, quantity])


func _build_explosion_result(notes: String) -> Dictionary:
	return {
		"output_id": "explosion",
		"quality": 0.0,
		"tier": "danger",
		"notes": notes,
	}


## Trigger an explosion: shake, burst sparks, damage nearby bodies, and reset the furnace.
func _trigger_explosion(notes: String, inputs_log: Array, temp: float) -> void:
	print("[FurnaceUI] EXPLOSION triggered at %d°C" % int(temp))

	if has_node("/root/CameraShake"):
		get_node("/root/CameraShake").shake.emit(
			FURNACE_EXPLOSION_SHAKE_STRENGTH,
			FURNACE_EXPLOSION_SHAKE_DURATION
		)

	_spawn_explosion_particles()

	for health_system in _get_overlapping_health_systems():
		health_system.take_damage(FURNACE_EXPLOSION_DAMAGE, &"explosion")

	var inventory_loss_text := ""
	if randf() < FURNACE_EXPLOSION_SLOT_LOSS_CHANCE:
		var destroyed_slot := InventoryManager.destroy_random_occupied_slot()
		if not destroyed_slot.is_empty():
			inventory_loss_text = " Lost slot %d: %s x%d." % [
				int(destroyed_slot.get("slot_index", 0)) + 1,
				_get_item_label(StringName(destroyed_slot.get("item_id", &""))),
				int(destroyed_slot.get("quantity", 0))
			]

	_reset_furnace_after_explosion()
	_slot_state[&"output"] = {&"item_id": &"", &"quantity": 0}
	_apply_slot_visual(&"output", &"", 0, "EXPLOSION!")

	action_hint_label.text = (
		notes if not notes.is_empty() else "Furnace overheated."
	) + inventory_loss_text

	var explosion_result := _build_explosion_result(action_hint_label.text)
	_log_to_discovery(explosion_result, inputs_log, temp)


func _spawn_explosion_particles() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var particles := GPUParticles2D.new()
	particles.amount = FURNACE_EXPLOSION_SPARK_COUNT
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = FURNACE_EXPLOSION_SPARK_LIFETIME
	particles.local_coords = false
	particles.texture = _get_explosion_spark_texture()
	particles.global_position = _get_furnace_world_position()

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(1.0, 0.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 90.0
	process_material.initial_velocity_max = 180.0
	process_material.gravity = Vector3.ZERO
	process_material.scale_min = 0.6
	process_material.scale_max = 1.3
	process_material.angular_velocity_min = -360.0
	process_material.angular_velocity_max = 360.0
	particles.process_material = process_material

	current_scene.add_child(particles)
	particles.global_position = _get_furnace_world_position()
	particles.emitting = true
	get_tree().create_timer(FURNACE_EXPLOSION_SPARK_LIFETIME + 0.2).timeout.connect(particles.queue_free)


func _get_overlapping_health_systems() -> Array:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return []

	var world := current_scene.get_world_2d()
	if world == null:
		return []

	var circle_shape := CircleShape2D.new()
	circle_shape.radius = FURNACE_EXPLOSION_RADIUS

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle_shape
	query.transform = Transform2D(0.0, _get_furnace_world_position())
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var results := world.direct_space_state.intersect_shape(query, 16)
	var health_systems: Array = []
	var seen := {}
	for result in results:
		var collider = result.get("collider")
		if not (collider is Node):
			continue

		var collider_node := collider as Node
		var health_system := collider_node.get_node_or_null("HealthSystem")
		if health_system == null:
			health_system = collider_node.find_child("HealthSystem", true, false)
		if health_system == null or not health_system.has_method("take_damage"):
			continue

		var instance_id := health_system.get_instance_id()
		if seen.has(instance_id):
			continue

		seen[instance_id] = true
		health_systems.append(health_system)

	return health_systems


func _reset_furnace_after_explosion() -> void:
	if is_instance_valid(_bound_furnace) and _bound_furnace.has_method("reset_after_explosion"):
		_bound_furnace.reset_after_explosion()
	else:
		_slot_state[&"input_a"] = {&"item_id": &"", &"quantity": 0}
		_slot_state[&"input_b"] = {&"item_id": &"", &"quantity": 0}
		_slot_state[&"fuel"] = {&"item_id": &"", &"quantity": 0}
		_apply_slot_visual(&"input_a", &"", 0, "No material")
		_apply_slot_visual(&"input_b", &"", 0, "No material")
		_apply_slot_visual(&"fuel", &"", 0, "Fuel item")
		_update_temperature_display(0.0)


func _get_furnace_world_position() -> Vector2:
	if is_instance_valid(_bound_furnace) and _bound_furnace is Node2D:
		return (_bound_furnace as Node2D).global_position
	return Vector2.ZERO


func _get_explosion_spark_texture() -> Texture2D:
	if _explosion_spark_texture != null:
		return _explosion_spark_texture

	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(4):
		for x in range(4):
			var is_core := x >= 1 and x <= 2 and y >= 1 and y <= 2
			var spark_color := Color8(255, 230, 160) if is_core else Color8(255, 140, 40, 180)
			image.set_pixel(x, y, spark_color)

	_explosion_spark_texture = ImageTexture.create_from_image(image)
	return _explosion_spark_texture


func _log_to_discovery(result: Dictionary, inputs: Array, temp: float) -> void:
	var log_node = get_node_or_null("/root/DiscoveryLog")
	if log_node:
		if log_node.has_method("log_smelt"):
			log_node.log_smelt(result, inputs, temp)
		else:
			push_error("DiscoveryLog is missing log_smelt method")
	else:
		push_error("DiscoveryLog autoload node not found under /root")


## Show tier-specific action hint feedback.
func _show_tier_feedback(output_id: StringName, tier: String) -> void:
	match tier:
		"optimal":
			if output_id == &"steel":
				action_hint_label.text = "Steel forged! Discovery logged."
			elif output_id == &"charcoal":
				action_hint_label.text = "Charcoal produced. Great fuel for the furnace."
		"low":
			action_hint_label.text = "Wrought Iron — soft, bends under load."
		"medium":
			action_hint_label.text = "Cast Iron — brittle. Failed steel attempt logged."
		"waste":
			if output_id == &"coke_slag":
				action_hint_label.text = "Coke Slag — too much carbon. Logged as 'Unknown compound'."
			else:
				action_hint_label.text = "Slag — overburned. Try a lower temperature."
		"danger":
			action_hint_label.text = "EXPLOSION! You've been burned."
		_:
			action_hint_label.text = "Reaction evaluated."


func _update_mode_state(is_carbonisation: bool) -> void:
	carbonisation_mode = is_carbonisation
	if not _is_initialized:
		return

	mode_label.text = "Carbonisation mode" if carbonisation_mode else "CONTROL"
	ratio_container.visible = not carbonisation_mode
	danger_zone.visible = not carbonisation_mode
	danger_line.visible = not carbonisation_mode
	carbon_slag_zone.visible = carbonisation_mode
	carbon_optimal_zone.visible = carbonisation_mode
	summary_label.text = (
		"Single-input wood carbonisation. Hold 400-700°C for charcoal; above 700°C overheats the furnace."
		if carbonisation_mode else
		"Load two materials, tune the B ratio, feed fuel, and watch the heat to preview the probable result."
	)
	action_hint_label.text = (
		"Single-input run: Slot B is empty, so the furnace is in carbonisation mode."
		if carbonisation_mode else
		"Combine two inputs, adjust the B ratio, and smelt to evaluate the alloy result."
	)
	_update_ratio_label(ratio_slider.value)
	_update_ratio_guidance()
	_update_temperature_display(_get_current_temperature())


func _should_use_carbonisation_mode() -> bool:
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	return int(input_b.get(&"quantity", 0)) <= 0


func _update_ratio_label(value: float) -> void:
	var source_info := _get_active_carbon_source_info()
	var source_symbol := str(source_info.get("symbol", "C"))
	ratio_value_label.text = "%s: %s%%" % [source_symbol, _format_pct(value)]


func _get_current_temperature() -> float:
	if is_instance_valid(_bound_furnace):
		return float(_bound_furnace.get("current_temp"))
	return 0.0


func _ensure_dynamic_ui_nodes() -> void:
	ratio_container = temperature_column_box.get_node_or_null("RatioContainer") as VBoxContainer
	if ratio_container == null:
		ratio_container = VBoxContainer.new()
		ratio_container.name = "RatioContainer"
		ratio_container.add_theme_constant_override("separation", 4)

		var ratio_title := Label.new()
		ratio_title.name = "RatioTitleLabel"
		ratio_title.text = "RATIO"
		ratio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ratio_title.add_theme_font_size_override("font_size", 13)
		ratio_container.add_child(ratio_title)

		ratio_graph_frame = Control.new()
		ratio_graph_frame.name = "RatioGraphFrame"
		ratio_graph_frame.custom_minimum_size = Vector2(0.0, 14.0)
		ratio_graph_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ratio_graph_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

		ratio_graph_background = ColorRect.new()
		ratio_graph_background.name = "RatioGraphBackground"
		ratio_graph_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_graph_background.anchor_right = 1.0
		ratio_graph_background.anchor_bottom = 1.0
		ratio_graph_background.offset_top = 2.0
		ratio_graph_background.offset_bottom = -2.0
		ratio_graph_background.color = RATIO_GUIDE_BG_COLOR
		ratio_graph_frame.add_child(ratio_graph_background)

		ratio_iron_fill = ColorRect.new()
		ratio_iron_fill.name = "RatioIronFill"
		ratio_iron_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_iron_fill.anchor_top = 0.0
		ratio_iron_fill.anchor_bottom = 1.0
		ratio_iron_fill.offset_top = 2.0
		ratio_iron_fill.offset_bottom = -2.0
		ratio_iron_fill.color = RATIO_IRON_FILL_COLOR
		ratio_graph_frame.add_child(ratio_iron_fill)

		ratio_carbon_fill = ColorRect.new()
		ratio_carbon_fill.name = "RatioCarbonFill"
		ratio_carbon_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_carbon_fill.anchor_top = 0.0
		ratio_carbon_fill.anchor_bottom = 1.0
		ratio_carbon_fill.offset_top = 2.0
		ratio_carbon_fill.offset_bottom = -2.0
		ratio_carbon_fill.color = RATIO_CARBON_FILL_COLOR
		ratio_graph_frame.add_child(ratio_carbon_fill)

		ratio_target_zone = ColorRect.new()
		ratio_target_zone.name = "RatioTargetZone"
		ratio_target_zone.visible = false
		ratio_target_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_target_zone.anchor_top = 0.0
		ratio_target_zone.anchor_bottom = 1.0
		ratio_target_zone.offset_top = 1.0
		ratio_target_zone.offset_bottom = -1.0
		ratio_target_zone.color = RATIO_GUIDE_TARGET_COLOR
		ratio_graph_frame.add_child(ratio_target_zone)

		ratio_current_marker = ColorRect.new()
		ratio_current_marker.name = "RatioCurrentMarker"
		ratio_current_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_current_marker.anchor_top = 0.0
		ratio_current_marker.anchor_bottom = 1.0
		ratio_current_marker.offset_left = -1.0
		ratio_current_marker.offset_right = 1.0
		ratio_current_marker.color = RATIO_GUIDE_MARKER_COLOR
		ratio_graph_frame.add_child(ratio_current_marker)
		ratio_container.add_child(ratio_graph_frame)

		ratio_slider = HSlider.new()
		ratio_slider.name = "RatioSlider"
		ratio_slider.min_value = CARBON_RATIO_MIN
		ratio_slider.max_value = CARBON_RATIO_MAX
		ratio_slider.step = 0.1
		ratio_slider.value = 1.0
		ratio_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ratio_container.add_child(ratio_slider)

		ratio_value_label = Label.new()
		ratio_value_label.name = "RatioValueLabel"
		ratio_value_label.text = "C: 1%"
		ratio_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ratio_container.add_child(ratio_value_label)

		temperature_column_box.add_child(ratio_container)
	else:
		ratio_graph_frame = ratio_container.get_node_or_null("RatioGraphFrame") as Control
		ratio_graph_background = ratio_container.get_node_or_null("RatioGraphFrame/RatioGraphBackground") as ColorRect
		ratio_iron_fill = ratio_container.get_node_or_null("RatioGraphFrame/RatioIronFill") as ColorRect
		ratio_carbon_fill = ratio_container.get_node_or_null("RatioGraphFrame/RatioCarbonFill") as ColorRect
		ratio_target_zone = ratio_container.get_node_or_null("RatioGraphFrame/RatioTargetZone") as ColorRect
		ratio_current_marker = ratio_container.get_node_or_null("RatioGraphFrame/RatioCurrentMarker") as ColorRect
		ratio_slider = ratio_container.get_node("RatioSlider") as HSlider
		ratio_value_label = ratio_container.get_node("RatioValueLabel") as Label

	if ratio_graph_frame == null:
		ratio_graph_frame = Control.new()
		ratio_graph_frame.name = "RatioGraphFrame"
		ratio_graph_frame.custom_minimum_size = Vector2(0.0, 14.0)
		ratio_graph_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ratio_graph_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

		ratio_graph_background = ColorRect.new()
		ratio_graph_background.name = "RatioGraphBackground"
		ratio_graph_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_graph_background.anchor_right = 1.0
		ratio_graph_background.anchor_bottom = 1.0
		ratio_graph_background.offset_top = 2.0
		ratio_graph_background.offset_bottom = -2.0
		ratio_graph_background.color = RATIO_GUIDE_BG_COLOR
		ratio_graph_frame.add_child(ratio_graph_background)

		ratio_iron_fill = ColorRect.new()
		ratio_iron_fill.name = "RatioIronFill"
		ratio_iron_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_iron_fill.anchor_top = 0.0
		ratio_iron_fill.anchor_bottom = 1.0
		ratio_iron_fill.offset_top = 2.0
		ratio_iron_fill.offset_bottom = -2.0
		ratio_iron_fill.color = RATIO_IRON_FILL_COLOR
		ratio_graph_frame.add_child(ratio_iron_fill)

		ratio_carbon_fill = ColorRect.new()
		ratio_carbon_fill.name = "RatioCarbonFill"
		ratio_carbon_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_carbon_fill.anchor_top = 0.0
		ratio_carbon_fill.anchor_bottom = 1.0
		ratio_carbon_fill.offset_top = 2.0
		ratio_carbon_fill.offset_bottom = -2.0
		ratio_carbon_fill.color = RATIO_CARBON_FILL_COLOR
		ratio_graph_frame.add_child(ratio_carbon_fill)

		ratio_target_zone = ColorRect.new()
		ratio_target_zone.name = "RatioTargetZone"
		ratio_target_zone.visible = false
		ratio_target_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_target_zone.anchor_top = 0.0
		ratio_target_zone.anchor_bottom = 1.0
		ratio_target_zone.offset_top = 1.0
		ratio_target_zone.offset_bottom = -1.0
		ratio_target_zone.color = RATIO_GUIDE_TARGET_COLOR
		ratio_graph_frame.add_child(ratio_target_zone)

		ratio_current_marker = ColorRect.new()
		ratio_current_marker.name = "RatioCurrentMarker"
		ratio_current_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ratio_current_marker.anchor_top = 0.0
		ratio_current_marker.anchor_bottom = 1.0
		ratio_current_marker.offset_left = -1.0
		ratio_current_marker.offset_right = 1.0
		ratio_current_marker.color = RATIO_GUIDE_MARKER_COLOR
		ratio_graph_frame.add_child(ratio_current_marker)
		ratio_container.add_child(ratio_graph_frame)
		ratio_container.move_child(ratio_graph_frame, 1)

	ratio_slider.min_value = CARBON_RATIO_MIN
	ratio_slider.max_value = CARBON_RATIO_MAX
	ratio_slider.step = 0.1

	carbon_slag_zone = gauge_frame.get_node_or_null("CarbonSlagZone") as ColorRect
	if carbon_slag_zone == null:
		carbon_slag_zone = ColorRect.new()
		carbon_slag_zone.name = "CarbonSlagZone"
		carbon_slag_zone.visible = false
		carbon_slag_zone.anchor_right = 1.0
		carbon_slag_zone.anchor_bottom = 0.65
		carbon_slag_zone.offset_left = 28.0
		carbon_slag_zone.offset_top = 6.0
		carbon_slag_zone.offset_right = -28.0
		carbon_slag_zone.offset_bottom = -2.0
		carbon_slag_zone.grow_horizontal = Control.GROW_DIRECTION_BOTH
		carbon_slag_zone.color = Color(0.89, 0.29, 0.24, 0.24)
		gauge_frame.add_child(carbon_slag_zone)

	carbon_optimal_zone = gauge_frame.get_node_or_null("CarbonOptimalZone") as ColorRect
	if carbon_optimal_zone == null:
		carbon_optimal_zone = ColorRect.new()
		carbon_optimal_zone.name = "CarbonOptimalZone"
		carbon_optimal_zone.visible = false
		carbon_optimal_zone.anchor_top = 0.65
		carbon_optimal_zone.anchor_right = 1.0
		carbon_optimal_zone.anchor_bottom = 0.8
		carbon_optimal_zone.offset_left = 28.0
		carbon_optimal_zone.offset_top = 2.0
		carbon_optimal_zone.offset_right = -28.0
		carbon_optimal_zone.offset_bottom = -2.0
		carbon_optimal_zone.grow_horizontal = Control.GROW_DIRECTION_BOTH
		carbon_optimal_zone.grow_vertical = Control.GROW_DIRECTION_BOTH
		carbon_optimal_zone.color = Color(0.34, 0.82, 0.45, 0.28)
		gauge_frame.add_child(carbon_optimal_zone)

	gauge_frame.move_child(danger_zone, 0)
	gauge_frame.move_child(carbon_slag_zone, 1)
	gauge_frame.move_child(carbon_optimal_zone, 2)
	gauge_frame.move_child(temperature_gauge, 3)
	gauge_frame.move_child(danger_line, 4)

	if ratio_graph_frame != null:
		ratio_graph_frame.move_child(ratio_graph_background, 0)
		ratio_graph_frame.move_child(ratio_iron_fill, 1)
		ratio_graph_frame.move_child(ratio_carbon_fill, 2)
		ratio_graph_frame.move_child(ratio_target_zone, 3)
		ratio_graph_frame.move_child(ratio_current_marker, 4)


func _update_ratio_guidance() -> void:
	if ratio_slider == null or ratio_value_label == null:
		return

	var guidance := _get_active_ratio_guidance()
	var tooltip := str(guidance.get("tooltip", RATIO_GUIDE_TOOLTIP_FALLBACK))
	ratio_container.tooltip_text = tooltip
	ratio_slider.tooltip_text = tooltip
	ratio_value_label.tooltip_text = tooltip

	var has_window := bool(guidance.get("has_window", false)) and not carbonisation_mode
	if ratio_target_zone != null:
		ratio_target_zone.visible = has_window
		if has_window:
			var ratio_min := float(guidance.get("ratio_min", 0.0))
			var ratio_max := float(guidance.get("ratio_max", 0.0))
			var min_anchor := inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, ratio_min)
			var max_anchor := inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, ratio_max)
			ratio_target_zone.anchor_left = clampf(min_anchor, 0.0, 1.0)
			ratio_target_zone.anchor_right = clampf(max_anchor, 0.0, 1.0)
			ratio_target_zone.offset_left = 0.0
			ratio_target_zone.offset_right = 0.0

	_update_ratio_bar_graph(ratio_slider.value)
	_update_ratio_current_marker(ratio_slider.value)


func _update_ratio_bar_graph(value: float) -> void:
	if ratio_iron_fill == null or ratio_carbon_fill == null or ratio_slider == null:
		return

	var normalized := clampf(inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, value), 0.0, 1.0)
	ratio_iron_fill.anchor_left = 0.0
	ratio_iron_fill.anchor_right = 1.0 - normalized
	ratio_iron_fill.offset_left = 0.0
	ratio_iron_fill.offset_right = 0.0

	ratio_carbon_fill.anchor_left = 1.0 - normalized
	ratio_carbon_fill.anchor_right = 1.0
	ratio_carbon_fill.offset_left = 0.0
	ratio_carbon_fill.offset_right = 0.0


func _update_ratio_current_marker(value: float) -> void:
	if ratio_current_marker == null or ratio_slider == null:
		return

	var normalized := clampf(inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, value), 0.0, 1.0)
	ratio_current_marker.anchor_left = normalized
	ratio_current_marker.anchor_right = normalized
	ratio_current_marker.offset_left = -1.0
	ratio_current_marker.offset_right = 1.0


func _get_active_ratio_guidance() -> Dictionary:
	if carbonisation_mode:
		return {
			"has_window": false,
			"tooltip": "Carbonisation mode: Slot B is empty."
		}

	var source_info := _get_active_carbon_source_info()
	if source_info.is_empty():
		return {
			"has_window": false,
			"tooltip": RATIO_GUIDE_TOOLTIP_FALLBACK
		}

	return _build_ratio_guidance(source_info)


func _build_ratio_guidance(source_info: Dictionary) -> Dictionary:
	var display_name := str(source_info.get("display_name", "Carbon source"))
	var carbon_fraction := clampf(float(source_info.get("carbon_fraction", 0.0)), 0.0, 1.0)
	var steel_window_min := float(source_info.get("steel_window_min_pct", 0.0))
	var steel_window_max := float(source_info.get("steel_window_max_pct", 0.0))
	if carbon_fraction <= 0.0:
		return {
			"has_window": false,
			"tooltip": "%s: no carbon profile available." % display_name
		}

	if steel_window_max <= steel_window_min:
		return {
			"has_window": false,
			"tooltip": "%s: steel window unavailable." % display_name
		}

	return {
		"has_window": true,
		"ratio_min": steel_window_min,
		"ratio_max": steel_window_max,
		"tooltip": "%s: steel at %s-%s%% carbon" % [
			display_name,
			_format_pct(steel_window_min),
			_format_pct(steel_window_max)
		]
	}


func _format_pct(value: float) -> String:
	var rounded_value := snappedf(value, 0.1)
	if is_equal_approx(rounded_value, roundf(rounded_value)):
		return str(int(round(rounded_value)))
	return "%.1f" % rounded_value


func _get_active_carbon_source_info() -> Dictionary:
	if carbonisation_mode:
		return {}

	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	if input_b_id.is_empty():
		return {}

	var element_data := ElementDatabase.get_element(input_b_id)
	if element_data.is_empty():
		return {}

	var properties: Dictionary = element_data.get(&"properties", {})
	var carbon_fraction := 0.0
	if properties.has(&"carbon_pct_when_burned"):
		carbon_fraction = float(properties.get(&"carbon_pct_when_burned", 0.0))
	elif properties.has(&"carbon_percentage"):
		carbon_fraction = float(properties.get(&"carbon_percentage", 0.0))
	else:
		return {}

	return {
		"element_id": input_b_id,
		"display_name": str(element_data.get(&"display_name", String(input_b_id).capitalize())),
		"symbol": str(element_data.get(&"symbol", "C")),
		"carbon_fraction": clampf(carbon_fraction, 0.0, 1.0),
		"steel_window_min_pct": maxf(float(properties.get(&"steel_window_carbon_min_pct", 0.0)), 0.0),
		"steel_window_max_pct": maxf(float(properties.get(&"steel_window_carbon_max_pct", 0.0)), 0.0)
	}


func _get_effective_b_ratio_from_slider(source_info: Dictionary) -> float:
	var carbon_fraction := clampf(float(source_info.get("carbon_fraction", 0.0)), 0.0, 1.0)
	if carbon_fraction <= 0.0:
		return 0.0
	return clampf(ratio_slider.value / carbon_fraction, 0.0, 100.0)


func _evaluate_alloy_prediction(input_a_id: StringName, input_b_id: StringName, current_temp: float) -> Dictionary:
	var source_info := _get_active_carbon_source_info()
	if source_info.is_empty():
		return {
			"output_id": null,
			"quality": 0.0,
			"tier": "unknown",
			"notes": "No carbon source profile"
		}

	return ChemistryEngine.evaluate_reaction(
		String(input_a_id),
		String(input_b_id),
		_get_effective_b_ratio_from_slider(source_info),
		current_temp
	)


func _show_output_prediction(result: Dictionary) -> void:
	var refs: Dictionary = _slot_refs.get(&"output", {})
	if refs.is_empty():
		return

	var output_id := StringName(str(result.get("output_id", "")))
	var notes := str(result.get("notes", ""))
	var prediction_text := notes if not notes.is_empty() else "No predicted output"
	if not output_id.is_empty():
		prediction_text = "Predicted: %s" % _get_item_label(output_id)

	var icon: TextureRect = refs[&"icon"]
	var quantity_label: Label = refs[&"quantity"]
	var name_label: Label = refs[&"name"]
	icon.texture = null
	icon.modulate = SLOT_EMPTY_COLOR
	quantity_label.text = ""
	name_label.text = prediction_text
	name_label.modulate = OUTPUT_PREVIEW_COLOR
