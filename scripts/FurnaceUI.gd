extends CanvasLayer

const DebugLog = preload("res://scripts/DebugLog.gd")
const FurnacePredictionScript = preload("res://scripts/FurnacePrediction.gd")
const FurnaceSlotControllerScript = preload("res://scripts/FurnaceSlotController.gd")
const FurnaceTheme = preload("res://scripts/FurnaceTheme.gd")
const FurnaceWarningFXScript = preload("res://scripts/FurnaceWarningFX.gd")

signal ui_closed
signal smelt_requested
signal forge_requested

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
const SMELT_BUTTON_COLOR := Color(0.79, 0.47, 0.18, 1.0)
const FORGE_BUTTON_COLOR := Color(0.39, 0.54, 0.74, 1.0)
const PANEL_VIEW_SCALE := 0.46
const PANEL_MARGIN := Vector2(24.0, 24.0)
const TOUCH_PANEL_MARGIN := 16.0
const RATIO_GUIDE_BG_COLOR := Color(0.18, 0.20, 0.23, 0.82)
const RATIO_IRON_FILL_COLOR := Color(0.34, 0.44, 0.52, 0.92)
const RATIO_CARBON_FILL_COLOR := Color(0.54, 0.31, 0.12, 0.96)
const RATIO_GUIDE_TARGET_COLOR := Color(0.34, 0.82, 0.45, 0.32)
const RATIO_GUIDE_MARKER_COLOR := Color(0.97, 0.97, 0.97, 0.95)
const OUTPUT_PREVIEW_COLOR := Color(0.58, 0.61, 0.66, 1.0)
const FURNACE_EXPLOSION_RADIUS := 32.0
const FURNACE_EXPLOSION_DAMAGE := 35
const FURNACE_EXPLOSION_SHAKE_STRENGTH := 1.2
const FURNACE_EXPLOSION_SHAKE_DURATION := 0.6
const FURNACE_EXPLOSION_SPARK_COUNT := 80
const FURNACE_EXPLOSION_SPARK_LIFETIME := 0.4
const FURNACE_EXPLOSION_SLOT_LOSS_CHANCE := 0.5
const SMELTING_FLASH_TEMPERATURE := 1500.0
const SMELTING_SFX_TEMPERATURE := 1580.0
const SMELTING_EXPLOSION_TEMPERATURE := 1600.0
const CARBONISATION_FLASH_TEMPERATURE := 650.0
const CARBONISATION_SFX_TEMPERATURE := 680.0
const CARBONISATION_SLAG_TEMPERATURE := 700.0
const WARNING_FLASH_SPEED := 0.014

@onready var root: Control = $Root
@onready var panel: PanelContainer = $Root/PanelContainer
@onready var title_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var summary_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/SummaryLabel
@onready var close_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/CloseButton
@onready var smelt_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/SmeltButton
@onready var forge_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/ForgeButton
@onready var recipe_cycle_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/RecipeCycleButton
@onready var fire_toggle_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/FireToggleButton
@onready var inventory_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/InventoryButton
@onready var action_hint_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/ActionHintLabel
@onready var fuel_cost_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/ActionColumn/MarginContainer/VBoxContainer/FuelCostLabel
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
var _burn_enabled := true
var _fuel_cost_state: Dictionary = {&"item_id": &"", &"burned_units": 0.0}
var _available_forge_output_ids: Array[StringName] = []
var _selected_forge_output_index := 0
var _power_status_label: Label
var _power_button: Button
var _power_state: Dictionary = {&"has_cell": false, &"charge_remaining_seconds": 0.0, &"switchboard_enabled": true, &"boost_active": false, &"grid_powered": false}
var _prediction := FurnacePredictionScript.new()
var _slot_controller := FurnaceSlotControllerScript.new()
var _warning_fx := FurnaceWarningFXScript.new()
var _slot_state: Dictionary[StringName, Dictionary] = {
	&"input_a": {&"item_id": &"", &"quantity": 0},
	&"input_b": {&"item_id": &"", &"quantity": 0},
	&"fuel": {&"item_id": &"", &"quantity": 0},
	&"output": {&"item_id": &"", &"quantity": 0},
}


func _ready() -> void:
	add_to_group(&"station_inventory_drop_target")
	_ensure_dynamic_ui_nodes()
	close_button.pressed.connect(_on_close_pressed)
	smelt_button.pressed.connect(_on_smelt_pressed)
	forge_button.pressed.connect(_on_forge_pressed)
	recipe_cycle_button.pressed.connect(_on_recipe_cycle_pressed)
	fire_toggle_button.pressed.connect(_on_fire_toggle_pressed)
	inventory_button.pressed.connect(_on_inventory_button_pressed)
	ratio_slider.value_changed.connect(_on_ratio_slider_changed)
	get_viewport().size_changed.connect(_layout_panel)

	_slot_refs = {
		&"input_a": _slot_controller.build_slot_ref(self, "InputSlotA"),
		&"input_b": _slot_controller.build_slot_ref(self, "InputSlotB"),
		&"fuel": _slot_controller.build_slot_ref(self, "FuelSlot"),
		&"output": _slot_controller.build_slot_ref(self, "OutputSlot"),
	}
	for slot_id: StringName in _slot_refs.keys():
		var slot_visual: Control = _slot_refs[slot_id].get(&"visual")
		if slot_visual != null and not slot_visual.gui_input.is_connected(_on_slot_gui_input.bind(slot_id)):
			slot_visual.gui_input.connect(_on_slot_gui_input.bind(slot_id))

	_apply_theme()
	_reset_slots()
	_warning_fx.ensure_audio_player(self)
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
	if event is InputEventKey and event.pressed and not event.echo and (
		event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK
	):
		close_ui()
		get_viewport().set_input_as_handled()


func open_ui() -> void:
	if not _is_initialized:
		call_deferred("open_ui")
		return
	_is_open = true
	if is_instance_valid(_bound_furnace):
		_pull_state_from_furnace()
	_update_mode_state(_should_use_carbonisation_mode())
	_layout_panel()
	root.visible = true
	call_deferred("_finalize_open_ui_layout")
	close_button.grab_focus()


func close_ui() -> void:
	if not _is_open:
		return
	_is_open = false
	root.visible = false
	ui_closed.emit()


func is_open() -> bool:
	return _is_open


func is_initialized() -> bool:
	return _is_initialized


func _layout_panel() -> void:
	if panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if MobileInputRouter != null and MobileInputRouter.prefers_touch_controls():
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.offset_left = TOUCH_PANEL_MARGIN
		panel.offset_top = TOUCH_PANEL_MARGIN
		panel.offset_right = -TOUCH_PANEL_MARGIN
		panel.offset_bottom = -TOUCH_PANEL_MARGIN
		panel.scale = Vector2.ONE
		panel.position = Vector2.ZERO
		return
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.pivot_offset = Vector2.ZERO
	panel.size = panel.custom_minimum_size
	panel.scale = Vector2(PANEL_VIEW_SCALE, PANEL_VIEW_SCALE)
	var scaled_size := panel.size * PANEL_VIEW_SCALE
	panel.position = Vector2(PANEL_MARGIN.x, maxf(PANEL_MARGIN.y, (viewport_size.y - scaled_size.y) * 0.5))


func _finalize_open_ui_layout() -> void:
	if not _is_open or panel == null:
		return
	_layout_panel()
	if MobileInputRouter == null or not MobileInputRouter.prefers_touch_controls():
		panel.scale = Vector2(PANEL_VIEW_SCALE, PANEL_VIEW_SCALE)


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

	var slot_id := _slot_controller.get_drop_slot_id(_slot_refs, global_mouse_position)
	if slot_id.is_empty():
		return false

	return _slot_controller.can_accept_drop_to_slot(_slot_state, slot_id, item_id, qty)


func handle_inventory_drop(global_mouse_position: Vector2, item_id: StringName, qty: int) -> bool:
	if not can_accept_inventory_drop(global_mouse_position, item_id, qty):
		return false

	var slot_id := _slot_controller.get_drop_slot_id(_slot_refs, global_mouse_position)
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


func set_fuel_cost_state(state: Dictionary) -> void:
	_fuel_cost_state = state.duplicate(true)
	_update_fuel_cost_indicator()


func set_burn_enabled(value: bool) -> void:
	_burn_enabled = value
	_update_fire_toggle_button()


func set_power_state(state: Dictionary) -> void:
	_power_state = state.duplicate(true)
	_update_power_panel()


func set_probable_output(item_id: StringName, quantity: int) -> void:
	_set_slot(&"output", item_id, quantity, "Awaiting recipe")


func show_output_placeholder(text: String) -> void:
	_slot_state[&"output"] = {&"item_id": &"", &"quantity": 0}
	_apply_slot_visual(&"output", &"", 0, text)
	_set_result_feedback(text)
	_update_action_button_states()


func _on_close_pressed() -> void:
	close_ui()


func _on_smelt_pressed() -> void:
	_evaluate_smelt_request()
	smelt_requested.emit()


func _on_forge_pressed() -> void:
	_evaluate_forge_request()
	forge_requested.emit()


func _on_recipe_cycle_pressed() -> void:
	var forge_outputs := _get_matching_forge_output_ids()
	if forge_outputs.size() <= 1:
		return
	_selected_forge_output_index = (_selected_forge_output_index + 1) % forge_outputs.size()
	_refresh_probable_output()
	_update_recipe_cycle_button()


func _on_fire_toggle_pressed() -> void:
	if not is_instance_valid(_bound_furnace) or not _bound_furnace.has_method("toggle_burn_enabled"):
		return
	_burn_enabled = bool(_bound_furnace.toggle_burn_enabled())
	_update_fire_toggle_button()
	_pull_state_from_furnace()


func _on_inventory_button_pressed() -> void:
	if MobileInputRouter != null:
		MobileInputRouter.tap_action(&"toggle_inventory")


func _on_ratio_slider_changed(value: float) -> void:
	_update_ratio_label(value)
	_update_ratio_guidance()
	_refresh_probable_output()


func _on_furnace_temp_changed(current_temp: float) -> void:
	if not _is_initialized:
		return
	_update_temperature_display(current_temp)
	_pull_state_from_furnace()


func _apply_theme() -> void:
	if not _is_initialized and temperature_gauge == null:
		return
	FurnaceTheme.apply(
		panel,
		_slot_refs,
		temperature_gauge,
		{
			"smelt": smelt_button,
			"forge": forge_button,
			"recipe_cycle": recipe_cycle_button,
			"fire_toggle": fire_toggle_button,
			"close": close_button,
		},
		{
			"title": title_label,
			"summary": summary_label,
			"temp": temp_readout_label,
			"action_hint": action_hint_label,
			"fuel_cost": fuel_cost_label,
			"mode": mode_label,
			"ratio_value": ratio_value_label,
			"danger": danger_label,
		},
		{
			"panel_bg": PANEL_BG_COLOR,
			"panel_border": PANEL_BORDER_COLOR,
			"slot_bg": SLOT_BG_COLOR,
			"slot_border": SLOT_BORDER_COLOR,
			"gauge_normal": GAUGE_NORMAL_COLOR,
			"gauge_danger": GAUGE_DANGER_COLOR,
			"smelt_button": SMELT_BUTTON_COLOR,
			"forge_button": FORGE_BUTTON_COLOR,
			"button_idle": BUTTON_IDLE_COLOR,
		}
	)


func _reset_slots() -> void:
	if not _is_initialized and _slot_refs.is_empty():
		return

	_apply_slot_visual(&"input_a", &"", 0, "No material")
	_apply_slot_visual(&"input_b", &"", 0, "No material")
	_apply_slot_visual(&"fuel", &"", 0, "Fuel item")
	_apply_slot_visual(&"output", &"", 0, "Awaiting recipe")
	_update_mode_state(false)
	_update_action_button_states()


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
	if _bound_furnace.has_method("is_burn_enabled"):
		set_burn_enabled(bool(_bound_furnace.is_burn_enabled()))
	if _bound_furnace.has_method("get_power_state"):
		set_power_state(_bound_furnace.get_power_state())
	_update_mode_state(_should_use_carbonisation_mode())
	_clear_output_if_stale()


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
	_update_action_button_states()


func _apply_slot_visual(slot_id: StringName, item_id: StringName, quantity: int, empty_label: String) -> void:
	_slot_controller.apply_slot_visual(_slot_refs, slot_id, item_id, quantity, empty_label)


func _refresh_probable_output() -> void:
	_update_mode_state(_should_use_carbonisation_mode())
	var preview := _prediction.build_output_preview(
		_slot_state,
		_get_current_temperature(),
		carbonisation_mode,
		ratio_slider.value,
		_available_forge_output_ids,
		_selected_forge_output_index,
		_get_charred_output_id(),
		Callable(ElementDatabase, "get_element"),
		Callable(self, "_get_item_label"),
		Callable(self, "_get_forge_lock_hint"),
		Callable(self, "_is_forge_recipe_unlocked"),
		Callable(ChemistryEngine, "evaluate_reaction")
	)
	_available_forge_output_ids = preview.get(&"available_forge_output_ids", [])
	_selected_forge_output_index = int(preview.get(&"selected_forge_output_index", 0))

	match str(preview.get(&"kind", "placeholder")):
		"output":
			var output_id := StringName(preview.get(&"output_id", &""))
			var quantity := int(preview.get(&"quantity", 0))
			_slot_state[&"output"] = {&"item_id": output_id, &"quantity": quantity}
			_apply_slot_visual(&"output", output_id, quantity, "Awaiting recipe")
			var action_hint := str(preview.get(&"action_hint", ""))
			if not action_hint.is_empty():
				action_hint_label.text = action_hint
		"prediction":
			_show_output_prediction(preview.get(&"prediction", {}))
		_:
			show_output_placeholder(str(preview.get(&"placeholder_text", "Awaiting recipe")))
			var action_hint := str(preview.get(&"action_hint", ""))
			if not action_hint.is_empty():
				action_hint_label.text = action_hint
	_update_recipe_cycle_button()


func _update_action_button_states() -> void:
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	var selection := _prediction.sync_forge_selection(_slot_state, _available_forge_output_ids, _selected_forge_output_index, Callable(self, "_is_forge_recipe_unlocked"))
	_available_forge_output_ids = selection.get(&"available_forge_output_ids", [])
	_selected_forge_output_index = int(selection.get(&"selected_forge_output_index", 0))
	var has_forge_recipe := not StringName(selection.get(&"selected_output_id", &"")).is_empty()
	var single_input := _get_single_input_state()
	var can_run_carbonisation := not single_input.is_empty() and StringName(single_input.get(&"item_id", &"")) == &"wood"
	forge_button.disabled = not has_forge_recipe
	smelt_button.disabled = has_forge_recipe or (
		not can_run_carbonisation if carbonisation_mode else (input_a_qty <= 0 or input_b_qty <= 0)
	)
	_update_recipe_cycle_button()
	_update_fire_toggle_button()


func _get_charred_output_id() -> StringName:
	if ElementDatabase.has_element(&"charcoal"):
		return &"charcoal"
	return &"pure_carbon"


func _update_temperature_display(current_temp: float) -> void:
	_warning_fx.update_temperature_display(
		current_temp,
		carbonisation_mode,
		{
			"temperature_gauge": temperature_gauge,
			"temp_readout_label": temp_readout_label,
			"danger_label": danger_label,
		},
		{
			"max_temperature": MAX_TEMPERATURE,
			"carbonisation_optimal_min": CARBONISATION_OPTIMAL_MIN,
			"carbonisation_slag_temperature": CARBONISATION_SLAG_TEMPERATURE,
			"carbonisation_flash_temperature": CARBONISATION_FLASH_TEMPERATURE,
			"carbonisation_sfx_temperature": CARBONISATION_SFX_TEMPERATURE,
			"carbonisation_good_color": CARBONISATION_GOOD_COLOR,
			"carbonisation_slag_color": CARBONISATION_SLAG_COLOR,
			"smelting_flash_temperature": SMELTING_FLASH_TEMPERATURE,
			"smelting_sfx_temperature": SMELTING_SFX_TEMPERATURE,
			"smelting_explosion_temperature": SMELTING_EXPLOSION_TEMPERATURE,
			"warning_flash_speed": WARNING_FLASH_SPEED,
			"gauge_normal_color": GAUGE_NORMAL_COLOR,
			"gauge_danger_color": GAUGE_DANGER_COLOR,
		}
	)


func _on_slot_gui_input(event: InputEvent, slot_id: StringName) -> void:
	if not _slot_controller.should_withdraw_from_gui_input(_is_open, event, slot_id):
		return
	_withdraw_slot_to_inventory(slot_id)
	get_viewport().set_input_as_handled()


func _withdraw_slot_to_inventory(slot_id: StringName) -> void:
	_slot_controller.withdraw_slot_to_inventory(_bound_furnace, slot_id, action_hint_label, Callable(self, "_get_item_label"))


func _get_item_label(item_id: StringName) -> String:
	return _slot_controller.get_item_label(item_id)


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

	_update_mode_state(_should_use_carbonisation_mode())

	if not _get_matching_forge_output_id().is_empty():
		show_output_placeholder("Use Forge")
		action_hint_label.text = "This recipe uses the Forge button."
		return

	# ── CARBONISATION PATH ───────────────────────────────────────────────────
	if carbonisation_mode:
		var single_input := _get_single_input_state()
		if single_input.is_empty() or StringName(single_input.get(&"item_id", &"")) != &"wood":
			show_output_placeholder("Load a single Wood stack")
			action_hint_label.text = "Carbonisation mode needs Wood in exactly one input slot."
			return
		var carbon_slot_id: StringName = single_input.get(&"slot_id", &"")
		var carbon_item_id: StringName = single_input.get(&"item_id", &"")
		var carbon_qty := int(single_input.get(&"quantity", 0))

		# Validate temperature range 400–700°C
		if current_temp < CARBONISATION_OPTIMAL_MIN:
			var carbonisation_result := ChemistryEngine.evaluate_reaction("wood", null, 0.0, current_temp)
			_last_reaction_result = carbonisation_result
			show_output_placeholder("No reaction")
			_set_result_feedback(
				str(carbonisation_result.get("notes", "Need 400–700°C for charcoal.")),
				str(carbonisation_result.get("notes", ""))
			)
			return

		if current_temp >= CARBONISATION_SLAG_TEMPERATURE:
			var slag_result := ChemistryEngine.evaluate_reaction("wood", null, 0.0, current_temp)
			_last_reaction_result = slag_result
			var slag_inputs_log := [{"item_id": carbon_item_id, "quantity": carbon_qty}]
			var slag_quantity := _consume_furnace_slot(carbon_slot_id, carbon_item_id, carbon_qty)
			_apply_reaction_result(slag_result, slag_quantity, slag_inputs_log, current_temp)
			return

		var carb_result := ChemistryEngine.evaluate_reaction("wood", null, 0.0, current_temp)
		_last_reaction_result = carb_result

		var consumed_a := _consume_furnace_slot(carbon_slot_id, carbon_item_id, carbon_qty)
		var inputs_log := [{"item_id": carbon_item_id, "quantity": consumed_a}]

		_apply_reaction_result(carb_result, consumed_a, inputs_log, current_temp)
		return

	# ── SMELTING PATH ────────────────────────────────────────────────────────
	if input_a_qty <= 0 or input_b_qty <= 0:
		show_output_placeholder("Load two materials")
		action_hint_label.text = "Smelting mode needs both input slots filled."
		return

	# Temperature >1600°C → explosion regardless of inputs
	if current_temp >= DANGER_TEMPERATURE:
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
		var too_cold_result := ChemistryEngine.evaluate_reaction(
			String(input_a_id),
			String(input_b_id),
			_get_effective_b_ratio_from_slider(_get_active_carbon_source_info()),
			current_temp
		)
		_last_reaction_result = too_cold_result
		show_output_placeholder("No reaction")
		_set_result_feedback(
			str(too_cold_result.get("notes", "Smelting requires 1200–1600°C.")),
			str(too_cold_result.get("notes", ""))
		)
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


func _evaluate_forge_request() -> void:
	var current_temp := 0.0
	if is_instance_valid(_bound_furnace):
		current_temp = float(_bound_furnace.get("current_temp"))

	var forge_output_id := _get_matching_forge_output_id()
	if forge_output_id.is_empty():
		show_output_placeholder("Load forge recipe")
		action_hint_label.text = "Forge supports tools and the Steel Sword."
		return

	if forge_output_id == FurnacePredictionScript.STEEL_SWORD_RECIPE_OUTPUT:
		_forge_steel_sword(current_temp)
		return
	_forge_tool(forge_output_id, current_temp)


## Consume `qty` of `item_id` from a furnace input slot and mirror to InventoryManager.
## Returns the actual quantity consumed.
func _consume_furnace_slot(slot_id: StringName, item_id: StringName, qty: int) -> int:
	if qty <= 0 or item_id.is_empty():
		return 0

	var actual_qty := qty

	# Update furnace internal state
	if is_instance_valid(_bound_furnace) and _bound_furnace.has_method("consume_input"):
		actual_qty = int(_bound_furnace.consume_input(slot_id, qty))
	elif is_instance_valid(_bound_furnace) and _bound_furnace.has_method("clear_input"):
		_bound_furnace.clear_input(slot_id)
	elif is_instance_valid(_bound_furnace):
		# Fallback: zero out the slot directly if clear_input is unavailable
		if _bound_furnace._input_slots.has(slot_id):
			_bound_furnace._input_slots[slot_id] = {&"item_id": &"", &"quantity": 0}

	if actual_qty <= 0:
		return 0

	# Update the local slot state to match the furnace.
	var local_slot: Dictionary = _slot_state.get(slot_id, {})
	var local_quantity := int(local_slot.get(&"quantity", 0))
	var remaining_qty: int = maxi(local_quantity - actual_qty, 0)
	if remaining_qty <= 0:
		_slot_state[slot_id] = {&"item_id": &"", &"quantity": 0}
		_apply_slot_visual(slot_id, &"", 0, "No material")
	else:
		_slot_state[slot_id] = {&"item_id": item_id, &"quantity": remaining_qty}
		var empty_label := "Fuel item" if slot_id == &"fuel" else "No material"
		_apply_slot_visual(slot_id, item_id, remaining_qty, empty_label)
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

	_set_result_feedback(notes if not notes.is_empty() else "Reaction evaluated.", notes)

	# ── EXPLOSION ────────────────────────────────────────────────────────────
	if output_id == &"explosion":
		_trigger_explosion(notes, inputs_log, temp)
		return

	# ── NO REACTION / FAILED TEMP CHECK ─────────────────────────────────────
	if output_id.is_empty():
		_capture_reaction_fuel_cost(0)
		show_output_placeholder(notes if not notes.is_empty() else "No reaction")
		_set_result_feedback(notes if not notes.is_empty() else "No reaction", notes)
		_log_to_discovery(result, inputs_log, temp)
		return

	# ── SUCCESSFUL REACTION ──────────────────────────────────────────────────
	var output_quantity := maxi(quantity, 1)

	# Deliver output to InventoryManager
	_deliver_output_to_inventory(output_id, output_quantity)
	_capture_reaction_fuel_cost(output_quantity)

	show_output_placeholder("Delivered to inventory")
	_set_result_feedback(notes if not notes.is_empty() else "Delivered to inventory", notes)
	_update_action_button_states()

	# Log to DiscoveryLog (emits signal, marks first discovery, etc.)
	_log_to_discovery(result, inputs_log, temp)

	# Tier-specific feedback
	_show_tier_feedback(output_id, tier)


## Deliver the smelted output to the player's InventoryManager.
func _deliver_output_to_inventory(output_id: StringName, quantity: int) -> void:
	if output_id.is_empty() or quantity <= 0:
		return

	if FurnacePredictionScript.TOOL_RECIPE_DEFINITIONS.has(output_id):
		var tool_item := _build_tool_item(output_id)
		var tool_added := InventoryManager.add_item(tool_item, quantity)
		if not tool_added:
			action_hint_label.text = "Inventory full! Output dropped on the floor."
			DebugLog.info("[FurnaceUI] Could not add %s x%d to inventory; capacity reached." % [output_id, quantity])
		return

	if output_id == FurnacePredictionScript.STEEL_SWORD_RECIPE_OUTPUT:
		var sword_item := {
			&"id": FurnacePredictionScript.STEEL_SWORD_RECIPE_OUTPUT,
			&"display_name": "Steel Sword",
			&"category": InventoryManager.InventoryItemCategory.CRAFTED,
			&"durability": 1.0,
			&"max_durability": 1.0,
			&"weapon_type": "melee",
			&"damage_type": "physical_sharp",
			&"base_damage": 10.0,
			&"attack_cooldown": 0.3,
		}
		var sword_added := InventoryManager.add_item(sword_item, quantity)
		if not sword_added:
			action_hint_label.text = "Inventory full! Output dropped on the floor."
			DebugLog.info("[FurnaceUI] Could not add %s x%d to inventory; capacity reached." % [output_id, quantity])
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
		DebugLog.info("[FurnaceUI] Could not add %s x%d to inventory; capacity reached." % [output_id, quantity])


func _build_explosion_result(notes: String) -> Dictionary:
	return {
		"output_id": "explosion",
		"quality": 0.0,
		"tier": "danger",
		"notes": notes,
	}


func _get_matching_tool_recipe_output_ids(include_locked: bool = false) -> Array[StringName]:
	return _prediction.get_matching_tool_recipe_output_ids(_slot_state, include_locked, Callable(self, "_is_forge_recipe_unlocked"))


func _get_matching_forge_output_ids(include_locked: bool = false) -> Array[StringName]:
	return _prediction.get_matching_forge_output_ids(_slot_state, include_locked, Callable(self, "_is_forge_recipe_unlocked"))


func _sync_forge_selection() -> void:
	var selection := _prediction.sync_forge_selection(_slot_state, _available_forge_output_ids, _selected_forge_output_index, Callable(self, "_is_forge_recipe_unlocked"))
	_available_forge_output_ids = selection.get(&"available_forge_output_ids", [])
	_selected_forge_output_index = int(selection.get(&"selected_forge_output_index", 0))


func _get_matching_forge_output_id() -> StringName:
	_sync_forge_selection()
	return StringName(_available_forge_output_ids[_selected_forge_output_index]) if not _available_forge_output_ids.is_empty() else &""


func _update_recipe_cycle_button() -> void:
	if not _is_initialized or recipe_cycle_button == null:
		return
	var forge_outputs := _get_matching_forge_output_ids()
	var has_multiple_outputs := forge_outputs.size() > 1
	recipe_cycle_button.visible = has_multiple_outputs
	recipe_cycle_button.disabled = not has_multiple_outputs
	if not has_multiple_outputs:
		recipe_cycle_button.text = "Recipe"
		return
	var selected_output_id := _get_matching_forge_output_id()
	recipe_cycle_button.text = "Recipe: %s (%d/%d)" % [
		_get_item_label(selected_output_id),
		_selected_forge_output_index + 1,
		forge_outputs.size(),
	]


func _forge_tool(output_id: StringName, current_temp: float) -> void:
	var recipe: Dictionary = _prediction.get_forge_recipe_definition(output_id)
	if recipe.is_empty():
		return

	var metal_id: StringName = recipe.get(&"metal_id", &"")
	var metal_qty := int(recipe.get(&"metal_qty", 0))
	var wood_qty := int(recipe.get(&"wood_qty", 0))
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	var metal_slot := &"input_a"
	var wood_slot := &"input_b"
	if input_b.get(&"item_id", &"") == metal_id:
		metal_slot = &"input_b"
		wood_slot = &"input_a"

	var consumed_metal := _consume_furnace_slot(metal_slot, metal_id, metal_qty)
	var consumed_wood := _consume_furnace_slot(wood_slot, &"wood", wood_qty)
	if consumed_metal < metal_qty or consumed_wood < wood_qty:
		show_output_placeholder("Load tool materials")
		action_hint_label.text = "%s forging needs %s x%d + Wood x%d." % [
			str(recipe.get(&"display_name", "Tool")),
			_get_item_label(metal_id),
			metal_qty,
			wood_qty,
		]
		return

	var forge_result := {
		"output_id": String(output_id),
		"quality": 1.0,
		"tier": "success",
		"notes": "%s forged. Harvesting effort reduced." % str(recipe.get(&"display_name", "Tool")),
	}
	_last_reaction_result = forge_result
	var inputs_log := [
		{"item_id": metal_id, "quantity": consumed_metal},
		{"item_id": &"wood", "quantity": consumed_wood},
	]
	_apply_reaction_result(forge_result, 1, inputs_log, current_temp)


func _build_tool_item(output_id: StringName) -> Dictionary:
	return _prediction.build_tool_item(output_id, InventoryManager.InventoryItemCategory.TOOL)


func _is_steel_sword_forge_ready() -> bool:
	return _prediction.is_steel_sword_forge_ready(_slot_state)


func _forge_steel_sword(current_temp: float) -> void:
	if not _is_steel_sword_unlocked():
		action_hint_label.text = _get_forge_lock_hint(FurnacePredictionScript.STEEL_SWORD_RECIPE_OUTPUT)
		return
	var source_slot: StringName = &"input_a"
	var source_state: Dictionary = _slot_state.get(source_slot, {})
	if source_state.get(&"item_id", &"") != FurnacePredictionScript.STEEL_SWORD_RECIPE_INPUT:
		source_slot = &"input_b"
		source_state = _slot_state.get(source_slot, {})
	if source_state.get(&"item_id", &"") != FurnacePredictionScript.STEEL_SWORD_RECIPE_INPUT:
		show_output_placeholder("Load Steel")
		action_hint_label.text = "Steel Sword forging needs Steel x1."
		return

	var consumed_qty := _consume_furnace_slot(source_slot, FurnacePredictionScript.STEEL_SWORD_RECIPE_INPUT, 1)
	if consumed_qty <= 0:
		show_output_placeholder("Load Steel")
		action_hint_label.text = "Steel Sword forging needs Steel x1."
		return

	var forge_result := {
		"output_id": String(FurnacePredictionScript.STEEL_SWORD_RECIPE_OUTPUT),
		"quality": 1.0,
		"tier": "success",
		"notes": "Steel Sword forged. Baseline melee output online.",
	}
	_last_reaction_result = forge_result
	var inputs_log := [{"item_id": FurnacePredictionScript.STEEL_SWORD_RECIPE_INPUT, "quantity": consumed_qty}]
	_apply_reaction_result(forge_result, 1, inputs_log, current_temp)


func _is_forge_recipe_unlocked(recipe: Dictionary) -> bool:
	if DiscoveryLog != null and DiscoveryLog.has_method("is_recipe_unlocked"):
		return bool(DiscoveryLog.is_recipe_unlocked(recipe))
	return true


func _is_steel_sword_unlocked() -> bool:
	return _prediction.is_steel_sword_unlocked(Callable(self, "_is_forge_recipe_unlocked"))


func _get_steel_sword_recipe_definition() -> Dictionary:
	return _prediction.get_steel_sword_recipe_definition()


func _get_forge_recipe_definition(output_id: StringName) -> Dictionary:
	return _prediction.get_forge_recipe_definition(output_id)


func _get_forge_lock_hint(output_id: StringName) -> String:
	var recipe := _get_forge_recipe_definition(output_id)
	if DiscoveryLog != null and DiscoveryLog.has_method("get_recipe_gate_hint"):
		var hint := str(DiscoveryLog.get_recipe_gate_hint(recipe))
		if not hint.is_empty():
			return hint
	return "Discover more about this material before forging it."


## Trigger an explosion: shake, burst sparks, damage nearby bodies, and reset the furnace.
func _trigger_explosion(notes: String, inputs_log: Array, temp: float) -> void:
	DebugLog.warning("[FurnaceUI] Explosion triggered at %d°C" % int(temp))

	var camera_shake := EventBus.get_camera_shake()
	if camera_shake != null and camera_shake.has_method("shake"):
		camera_shake.shake(
			FURNACE_EXPLOSION_SHAKE_STRENGTH,
			FURNACE_EXPLOSION_SHAKE_DURATION
		)

	_spawn_explosion_particles()

	for health_system in _get_overlapping_health_systems():
		health_system.take_damage(FURNACE_EXPLOSION_DAMAGE, &"explosion", "Furnace explosion")

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

	var world: World2D = current_scene.get_world_2d()
	if world == null:
		return []

	var circle_shape := CircleShape2D.new()
	circle_shape.radius = FURNACE_EXPLOSION_RADIUS

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle_shape
	query.transform = Transform2D(0.0, _get_furnace_world_position())
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var results: Array = world.direct_space_state.intersect_shape(query, 16)
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
	var output_id := StringName(str(result.get("output_id", "")))
	if log_node:
		if log_node.has_method("log_smelt"):
			log_node.log_smelt(result, inputs, temp)
		else:
			push_error("DiscoveryLog is missing log_smelt method")
	else:
		push_error("DiscoveryLog autoload node not found under /root")

	var event_bus = get_node_or_null("/root/EventBus")
	if not output_id.is_empty() and event_bus != null and event_bus.has_method("emit_discovery_made"):
		event_bus.emit_discovery_made(output_id)


## Show tier-specific action hint feedback.
func _show_tier_feedback(output_id: StringName, tier: String) -> void:
	match tier:
		"optimal":
			if output_id == &"steel":
				_set_result_feedback("Steel forged! Discovery logged.")
			elif output_id == &"charcoal":
				_set_result_feedback("Charcoal produced. Great fuel for the furnace.")
		"low":
			_set_result_feedback("Wrought Iron — soft, bends under load.")
		"medium":
			_set_result_feedback("Cast Iron — brittle. Failed steel attempt logged.")
		"waste":
			if output_id == &"coke_slag":
				_set_result_feedback("Coke Slag — too much carbon. Logged as 'Unknown compound'.")
			else:
				_set_result_feedback("Slag — overburned. Try a lower temperature.")
		"danger":
			_set_result_feedback("EXPLOSION! You've been burned.")
		_:
			_set_result_feedback("Reaction evaluated.")


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
		"Single-input wood carbonisation. Hold 400-699°C for charcoal; at 700°C the wood burns into Slag."
		if carbonisation_mode else
		"Load two materials, tune the B ratio, feed fuel, and watch the heat to preview the probable result."
	)
	action_hint_label.text = (
		"Single-input wood run detected. Use either input slot, but only one at a time."
		if carbonisation_mode else
		"Combine two inputs, adjust the B ratio, and smelt to evaluate the alloy result."
	)
	_update_ratio_label(ratio_slider.value)
	_update_ratio_guidance()
	_update_temperature_display(_get_current_temperature())


func _should_use_carbonisation_mode() -> bool:
	var single_input := _get_single_input_state()
	return not single_input.is_empty() and StringName(single_input.get(&"item_id", &"")) == &"wood"


func _get_single_input_state() -> Dictionary:
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	if input_a_qty > 0 and input_b_qty <= 0:
		return {
			&"slot_id": &"input_a",
			&"item_id": input_a.get(&"item_id", &""),
			&"quantity": input_a_qty,
		}
	if input_b_qty > 0 and input_a_qty <= 0:
		return {
			&"slot_id": &"input_b",
			&"item_id": input_b.get(&"item_id", &""),
			&"quantity": input_b_qty,
		}
	return {}


func _update_fire_toggle_button() -> void:
	if fire_toggle_button == null:
		return
	var fuel_state: Dictionary = _slot_state.get(&"fuel", {})
	var has_fuel := int(fuel_state.get(&"quantity", 0)) > 0
	fire_toggle_button.disabled = not has_fuel
	fire_toggle_button.text = "Fire: On" if _burn_enabled and has_fuel else "Fire: Off"


func _set_result_feedback(text: String, notes: String = "") -> void:
	action_hint_label.text = text
	var tooltip_text := notes if not notes.is_empty() else text
	action_hint_label.tooltip_text = tooltip_text
	var output_refs: Dictionary = _slot_refs.get(&"output", {})
	if not output_refs.is_empty():
		var output_panel: Control = output_refs.get(&"panel")
		var output_name: Label = output_refs.get(&"name")
		if output_panel != null:
			output_panel.tooltip_text = tooltip_text
		if output_name != null:
			output_name.tooltip_text = tooltip_text


func _update_fuel_cost_indicator() -> void:
	if fuel_cost_label == null:
		return
	fuel_cost_label.text = _format_fuel_cost_text(_fuel_cost_state)
	fuel_cost_label.tooltip_text = fuel_cost_label.text


func _capture_reaction_fuel_cost(output_quantity: int) -> void:
	if is_instance_valid(_bound_furnace) and _bound_furnace.has_method("commit_reaction_fuel_cost"):
		_fuel_cost_state = _bound_furnace.commit_reaction_fuel_cost()
	_fuel_cost_state[&"output_quantity"] = output_quantity
	_update_fuel_cost_indicator()


func _format_fuel_cost_text(state: Dictionary) -> String:
	var fuel_item_id: StringName = state.get(&"item_id", &"")
	var burned_units := float(state.get(&"burned_units", 0.0))
	var output_quantity := int(state.get(&"output_quantity", 0))
	if fuel_item_id.is_empty() or burned_units <= 0.0:
		return "Fuel cost: waiting on burn"

	var fuel_name := _get_item_label(fuel_item_id)
	var burned_text := _format_pct(burned_units)
	if output_quantity > 0:
		return "Fuel cost: %s %s for %d output" % [burned_text, fuel_name, output_quantity]
	return "Fuel cost: %s %s burned so far" % [burned_text, fuel_name]


func _clear_output_if_stale() -> void:
	var output_state: Dictionary = _slot_state.get(&"output", {})
	if int(output_state.get(&"quantity", 0)) <= 0:
		return
	var input_a: Dictionary = _slot_state.get(&"input_a", {})
	var input_b: Dictionary = _slot_state.get(&"input_b", {})
	var fuel: Dictionary = _slot_state.get(&"fuel", {})
	var has_inputs := int(input_a.get(&"quantity", 0)) > 0 or int(input_b.get(&"quantity", 0)) > 0
	var has_fuel := int(fuel.get(&"quantity", 0)) > 0
	if not has_inputs and not has_fuel:
		show_output_placeholder("Awaiting recipe")


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

	_power_status_label = close_button.get_parent().get_node_or_null("PowerStatusLabel") as Label
	_power_button = close_button.get_parent().get_node_or_null("PowerButton") as Button
	if _power_status_label == null:
		_power_status_label = Label.new()
		_power_status_label.name = "PowerStatusLabel"
		_power_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_power_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		close_button.get_parent().add_child(_power_status_label)
		close_button.get_parent().move_child(_power_status_label, close_button.get_index())
	if _power_button == null:
		_power_button = Button.new()
		_power_button.name = "PowerButton"
		_power_button.text = "Insert Energy Cell"
		_power_button.pressed.connect(_on_power_button_pressed)
		close_button.get_parent().add_child(_power_button)
		close_button.get_parent().move_child(_power_button, close_button.get_index())
	_update_power_panel()


func _update_power_panel() -> void:
	if _power_status_label == null or _power_button == null:
		return
	var switchboard_enabled := bool(_power_state.get(&"switchboard_enabled", true))
	var boost_active := bool(_power_state.get(&"boost_active", false))
	var grid_powered := bool(_power_state.get(&"grid_powered", false))
	if boost_active:
		_power_status_label.text = "Grid boost active\nHigher heat cap, faster rise, lower fuel burn."
	elif not switchboard_enabled:
		_power_status_label.text = "Boost disabled at the battery station switchboard."
	elif not grid_powered:
		_power_status_label.text = "Boost available through the battery station.\nCharge the defense grid to enable it."
	else:
		_power_status_label.text = "Boost is managed by the battery station switchboard."
	_power_button.text = "Managed at Battery Station"
	_power_button.disabled = true


func _on_power_button_pressed() -> void:
	return


func _update_ratio_guidance() -> void:
	if ratio_slider == null or ratio_value_label == null:
		return

	var guidance := _get_active_ratio_guidance()
	var tooltip := str(guidance.get("tooltip", FurnacePredictionScript.RATIO_GUIDE_TOOLTIP_FALLBACK))
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
	return _prediction.get_active_ratio_guidance(carbonisation_mode, _get_active_carbon_source_info())


func _build_ratio_guidance(source_info: Dictionary) -> Dictionary:
	return _prediction.build_ratio_guidance(source_info)


func _format_pct(value: float) -> String:
	return _prediction.format_pct(value)


func _get_active_carbon_source_info() -> Dictionary:
	return _prediction.get_active_carbon_source_info(_slot_state, carbonisation_mode, Callable(ElementDatabase, "get_element"))


func _get_effective_b_ratio_from_slider(source_info: Dictionary) -> float:
	return _prediction.get_effective_b_ratio(ratio_slider.value, source_info)


func _evaluate_alloy_prediction(input_a_id: StringName, input_b_id: StringName, current_temp: float) -> Dictionary:
	return _prediction.evaluate_alloy_prediction(input_a_id, input_b_id, current_temp, ratio_slider.value, _get_active_carbon_source_info(), Callable(ChemistryEngine, "evaluate_reaction"))


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
