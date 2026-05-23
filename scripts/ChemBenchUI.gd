extends CanvasLayer

signal ui_closed

const SLOT_EMPTY_TEXT := {
	&"input_a": "Iron filings",
	&"input_b": "Oxide wash",
	&"output": "Rust Bolt",
}
const SLOT_PANEL_COLOR := Color(0.18, 0.19, 0.22, 1.0)
const SLOT_FILLED_COLOR := Color(0.24, 0.31, 0.36, 1.0)
const SLOT_OUTPUT_READY_COLOR := Color(0.34, 0.28, 0.15, 1.0)

@onready var root: Control = $Root
@onready var backdrop: ColorRect = $Root/Backdrop
@onready var panel: PanelContainer = $Root/PanelContainer
@onready var title_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var summary_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/SummaryLabel
@onready var recipe_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/RecipePlate/RecipeLabel
@onready var input_a_visual: Panel = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/InputVialA/MarginContainer/VBoxContainer/VialVisual
@onready var input_a_name_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/InputVialA/MarginContainer/VBoxContainer/ItemNameLabel
@onready var input_b_visual: Panel = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/InputVialB/MarginContainer/VBoxContainer/VialVisual
@onready var input_b_name_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/InputVialB/MarginContainer/VBoxContainer/ItemNameLabel
@onready var output_visual: Panel = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/OutputFlask/MarginContainer/VBoxContainer/FlaskVisual
@onready var output_name_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/OutputFlask/MarginContainer/VBoxContainer/ItemNameLabel
@onready var ratio_slider: HSlider = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/RatioSlider
@onready var ratio_value_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/RatioValueLabel
@onready var react_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/ReactButton
@onready var close_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FooterRow/CloseButton

var _chem_bench: Node = null
var _slot_state: Dictionary[StringName, Dictionary] = {
	&"input_a": {&"item_id": &"", &"quantity": 0},
	&"input_b": {&"item_id": &"", &"quantity": 0},
}


func _ready() -> void:
	visible = false
	root.visible = false
	_apply_theme()
	_refresh_slot_visuals()
	_update_ratio_label(ratio_slider.value)
	ratio_slider.value_changed.connect(_on_ratio_slider_changed)
	react_button.pressed.connect(_on_react_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		emit_signal("ui_closed")
		get_viewport().set_input_as_handled()


func bind_chem_bench(chem_bench: Node) -> void:
	_chem_bench = chem_bench
	if _chem_bench != null and _chem_bench.has_method("get_active_recipe"):
		var recipe: Dictionary = _chem_bench.get_active_recipe()
		recipe_label.text = "ACTIVE RECIPE: %s" % str(recipe.get(&"display_name", "Rust Bolt"))


func open_ui() -> void:
	visible = true
	root.visible = true


func close_ui() -> void:
	root.visible = false
	visible = false


func _on_ratio_slider_changed(value: float) -> void:
	_update_ratio_label(value)


func _on_react_button_pressed() -> void:
	if not _can_craft_active_recipe():
		react_button.text = "Need 2 Iron + 1 Water"
		return

	var output_item := {
		&"id": &"rust_bolt",
		&"display_name": "Rust Bolt",
		&"category": InventoryManager.InventoryItemCategory.CONSUMABLE,
	}
	if not InventoryManager.add_item(output_item, 8):
		react_button.text = "Inventory Full"
		return

	_clear_inputs()
	output_name_label.text = "Rust Bolt x8"
	_apply_slot_panel_style(output_visual, SLOT_OUTPUT_READY_COLOR)
	react_button.text = "Rust Bolt Crafted"


func _on_close_button_pressed() -> void:
	emit_signal("ui_closed")


func can_accept_inventory_drop(global_mouse_position: Vector2, item_id: StringName, qty: int) -> bool:
	if not visible or qty <= 0 or item_id.is_empty():
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

	_slot_state[slot_id] = {
		&"item_id": item_id,
		&"quantity": qty,
	}
	_refresh_slot_visuals()
	react_button.text = "React"
	return true


func _update_ratio_label(value: float) -> void:
	ratio_value_label.text = "Reagent Ratio: %.0f / %.0f" % [value, ratio_slider.max_value]


func _apply_theme() -> void:
	backdrop.color = Color(0.01, 0.02, 0.03, 0.54)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.10, 0.97)
	panel_style.border_color = Color(0.42, 0.35, 0.21, 1.0)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", panel_style)

	title_label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.63, 1.0))
	summary_label.add_theme_color_override("font_color", Color(0.70, 0.72, 0.68, 1.0))
	recipe_label.add_theme_color_override("font_color", Color(0.82, 0.66, 0.34, 1.0))
	ratio_value_label.add_theme_color_override("font_color", Color(0.76, 0.81, 0.76, 1.0))

	var react_style := StyleBoxFlat.new()
	react_style.bg_color = Color(0.34, 0.22, 0.12, 1.0)
	react_style.border_color = Color(0.78, 0.55, 0.24, 1.0)
	react_style.border_width_left = 1
	react_style.border_width_right = 1
	react_style.border_width_top = 1
	react_style.border_width_bottom = 1
	react_style.corner_radius_top_left = 6
	react_style.corner_radius_top_right = 6
	react_style.corner_radius_bottom_left = 6
	react_style.corner_radius_bottom_right = 6
	react_button.add_theme_stylebox_override("normal", react_style)
	react_button.add_theme_stylebox_override("hover", react_style)
	react_button.add_theme_stylebox_override("pressed", react_style)


func _get_drop_slot_id(global_mouse_position: Vector2) -> StringName:
	for slot_id: StringName in [&"input_a", &"input_b"]:
		var slot_visual := _get_slot_visual(slot_id)
		if slot_visual == null:
			continue
		if slot_visual.get_global_rect().has_point(global_mouse_position):
			return slot_id
	return &""


func _can_accept_drop_to_slot(slot_id: StringName, item_id: StringName, qty: int) -> bool:
	if qty <= 0 or item_id.is_empty():
		return false

	match slot_id:
		&"input_a":
			if item_id != &"iron" or qty > 2:
				return false
		&"input_b":
			if item_id != &"water" or qty > 1:
				return false
		_:
			return false

	var existing: Dictionary = _slot_state.get(slot_id, {})
	var current_item_id: StringName = existing.get(&"item_id", &"")
	return current_item_id.is_empty() or current_item_id == item_id


func _can_craft_active_recipe() -> bool:
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	return input_a.get(&"item_id", &"") == &"iron" and int(input_a.get(&"quantity", 0)) == 2 and input_b.get(&"item_id", &"") == &"water" and int(input_b.get(&"quantity", 0)) == 1


func _clear_inputs() -> void:
	_slot_state[&"input_a"] = {&"item_id": &"", &"quantity": 0}
	_slot_state[&"input_b"] = {&"item_id": &"", &"quantity": 0}
	_refresh_slot_visuals()


func _refresh_slot_visuals() -> void:
	_apply_slot_state(&"input_a", input_a_name_label, input_a_visual)
	_apply_slot_state(&"input_b", input_b_name_label, input_b_visual)
	if not _can_craft_active_recipe():
		output_name_label.text = SLOT_EMPTY_TEXT[&"output"]
		_apply_slot_panel_style(output_visual, SLOT_PANEL_COLOR)


func _apply_slot_state(slot_id: StringName, label: Label, visual: Panel) -> void:
	var slot_state: Dictionary = _slot_state.get(slot_id, {})
	var item_id: StringName = slot_state.get(&"item_id", &"")
	var quantity := int(slot_state.get(&"quantity", 0))
	if item_id.is_empty() or quantity <= 0:
		label.text = SLOT_EMPTY_TEXT[slot_id]
		_apply_slot_panel_style(visual, SLOT_PANEL_COLOR)
		return
	label.text = "%s x%d" % [_get_item_name(item_id), quantity]
	_apply_slot_panel_style(visual, SLOT_FILLED_COLOR)


func _apply_slot_panel_style(panel_node: Panel, bg_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color(0.44, 0.39, 0.24, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel_node.add_theme_stylebox_override("panel", style)


func _get_slot_visual(slot_id: StringName) -> Panel:
	match slot_id:
		&"input_a":
			return input_a_visual
		&"input_b":
			return input_b_visual
	return null


func _get_item_name(item_id: StringName) -> String:
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", item_id))
	return String(item_id).replace("_", " ").capitalize()
