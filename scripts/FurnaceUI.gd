extends CanvasLayer

signal ui_closed
signal smelt_requested

const MAX_TEMPERATURE := 2000.0
const DANGER_TEMPERATURE := 1600.0
const WOOD_HEAT_POTENTIAL := 200.0
const PANEL_BG_COLOR := Color(0.10, 0.11, 0.13, 0.96)
const PANEL_BORDER_COLOR := Color(0.28, 0.30, 0.34, 1.0)
const SLOT_BG_COLOR := Color(0.14, 0.16, 0.19, 1.0)
const SLOT_BORDER_COLOR := Color(0.34, 0.37, 0.41, 1.0)
const SLOT_EMPTY_COLOR := Color(0.52, 0.55, 0.60, 1.0)
const GAUGE_NORMAL_COLOR := Color(0.95, 0.62, 0.22, 1.0)
const GAUGE_DANGER_COLOR := Color(0.89, 0.29, 0.24, 1.0)
const BUTTON_IDLE_COLOR := Color(0.28, 0.30, 0.35, 1.0)
const BUTTON_HOVER_COLOR := Color(0.36, 0.39, 0.45, 1.0)
const BUTTON_PRESSED_COLOR := Color(0.22, 0.24, 0.28, 1.0)
const SMELT_BUTTON_COLOR := Color(0.79, 0.47, 0.18, 1.0)

@onready var root: Control = $Root
@onready var panel: PanelContainer = $Root/PanelContainer
@onready var title_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var summary_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/SummaryLabel
@onready var close_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/CloseButton
@onready var smelt_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/SmeltButton
@onready var action_hint_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/ActionHintLabel
@onready var temp_readout_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/TemperatureReadout
@onready var danger_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/DangerLabel
@onready var temperature_gauge: ProgressBar = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/TemperatureColumn/MarginContainer/VBoxContainer/GaugeFrame/TemperatureGauge

var _is_open := false
var _is_initialized := false
var _bound_furnace: Node
var _placeholder_textures := {}
var _slot_refs: Dictionary[StringName, Dictionary] = {}
var _slot_state: Dictionary[StringName, Dictionary] = {
	&"input_a": {&"item_id": &"", &"quantity": 0},
	&"input_b": {&"item_id": &"", &"quantity": 0},
	&"fuel": {&"item_id": &"", &"quantity": 0},
	&"output": {&"item_id": &"", &"quantity": 0},
}


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	smelt_button.pressed.connect(_on_smelt_pressed)

	_slot_refs = {
		&"input_a": _build_slot_ref("InputSlotA"),
		&"input_b": _build_slot_ref("InputSlotB"),
		&"fuel": _build_slot_ref("FuelSlot"),
		&"output": _build_slot_ref("OutputSlot"),
	}

	_apply_theme()
	_reset_slots()
	_update_temperature_display(0.0)
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


func set_input_slot_a(item_id: StringName, quantity: int) -> void:
	_set_slot(&"input_a", item_id, quantity, "No material")


func set_input_slot_b(item_id: StringName, quantity: int) -> void:
	_set_slot(&"input_b", item_id, quantity, "No material")


func set_fuel_slot(item_id: StringName, quantity: int) -> void:
	if quantity > 0 and item_id != &"wood":
		return
	_set_slot(&"fuel", item_id, quantity, "Wood only")


func set_probable_output(item_id: StringName, quantity: int) -> void:
	_set_slot(&"output", item_id, quantity, "Awaiting recipe")


func show_output_placeholder(text: String) -> void:
	_slot_state[&"output"] = {&"item_id": &"", &"quantity": 0}
	_apply_slot_visual(&"output", &"", 0, text)
	_update_smelt_button_state()


func _on_close_pressed() -> void:
	close_ui()


func _on_smelt_pressed() -> void:
	smelt_requested.emit()


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

		var slot_visual: PanelContainer = _slot_refs[slot_id][&"visual"]
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
	_apply_slot_visual(&"fuel", &"", 0, "Wood only")
	_apply_slot_visual(&"output", &"", 0, "Awaiting recipe")
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

	var fuel_potential = _bound_furnace.get("fuel_level")
	if fuel_potential == null:
		return

	var remaining_potential := maxf(float(fuel_potential), 0.0)
	if remaining_potential <= 0.0:
		set_fuel_slot(&"", 0)
	else:
		set_fuel_slot(&"wood", maxi(1, int(ceil(remaining_potential / WOOD_HEAT_POTENTIAL))))


func _set_slot(slot_id: StringName, item_id: StringName, quantity: int, empty_label: String) -> void:
	if not _is_initialized:
		return

	var clamped_quantity := maxi(quantity, 0)
	_slot_state[slot_id] = {
		&"item_id": item_id if clamped_quantity > 0 else &"",
		&"quantity": clamped_quantity,
	}
	_apply_slot_visual(slot_id, item_id, clamped_quantity, empty_label)
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
	var fuel: Dictionary = _slot_state.get(&"fuel", {})

	var input_a_id: StringName = input_a.get(&"item_id", &"")
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	var fuel_qty := int(fuel.get(&"quantity", 0))

	if input_a_qty <= 0 and input_b_qty <= 0:
		show_output_placeholder("Awaiting recipe")
		return

	if fuel_qty <= 0:
		show_output_placeholder("Load wood fuel")
		return

	if input_b_qty <= 0 and input_a_id == &"wood":
		_slot_state[&"output"] = {&"item_id": &"pure_carbon", &"quantity": maxi(1, input_a_qty)}
		_apply_slot_visual(&"output", &"pure_carbon", maxi(1, input_a_qty), "Awaiting recipe")
		return

	if input_a_qty <= 0 and input_b_id == &"wood":
		_slot_state[&"output"] = {&"item_id": &"pure_carbon", &"quantity": maxi(1, input_b_qty)}
		_apply_slot_visual(&"output", &"pure_carbon", maxi(1, input_b_qty), "Awaiting recipe")
		return

	show_output_placeholder("Unknown output")


func _update_smelt_button_state() -> void:
	var output_state: Dictionary = _slot_state.get(&"output", {})
	smelt_button.disabled = int(output_state.get(&"quantity", 0)) <= 0


func _update_temperature_display(current_temp: float) -> void:
	if temperature_gauge == null or temp_readout_label == null or danger_label == null:
		return

	var clamped_temp := clampf(current_temp, 0.0, MAX_TEMPERATURE)
	var is_danger := clamped_temp >= DANGER_TEMPERATURE

	temperature_gauge.value = clamped_temp
	temp_readout_label.text = "%d°C" % int(round(clamped_temp))
	temp_readout_label.add_theme_color_override("font_color", GAUGE_DANGER_COLOR if is_danger else GAUGE_NORMAL_COLOR)

	var fill_style: StyleBoxFlat = temperature_gauge.get_theme_stylebox("fill").duplicate()
	fill_style.bg_color = GAUGE_DANGER_COLOR if is_danger else GAUGE_NORMAL_COLOR
	temperature_gauge.add_theme_stylebox_override("fill", fill_style)
	danger_label.visible = is_danger


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
