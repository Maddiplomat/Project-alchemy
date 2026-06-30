extends CanvasLayer

signal ui_closed

const STABILIZATION_MINIGAME_SCENE := preload("res://scenes/UI/StabilizationMinigame.tscn")
const SLOT_PANEL_COLOR := Color(0.18, 0.19, 0.22, 1.0)
const SLOT_FILLED_COLOR := Color(0.24, 0.31, 0.36, 1.0)
const SLOT_OUTPUT_READY_COLOR := Color(0.34, 0.28, 0.15, 1.0)
const SLOT_OUTPUT_DANGER_COLOR := Color(0.42, 0.13, 0.10, 1.0)
const SLOT_OUTPUT_UNKNOWN_COLOR := Color(0.21, 0.23, 0.25, 1.0)
const SLOT_EMPTY_TEXT := {
	&"input_a": "Input A",
	&"input_b": "Input B",
	&"catalyst": "Catalyst",
	&"output": "Awaiting reaction",
}
const TEMPERATURE_MIN := 20.0
const TEMPERATURE_MAX := 260.0
const PANEL_VIEW_SCALE := 0.62
const PANEL_MARGIN := Vector2(24.0, 24.0)
const RATIO_TARGET_INPUT_A := &"input_a"
const RATIO_TARGET_INPUT_B := &"input_b"
const STABILIZATION_DISCOVERY_ID := &"stabilization_success"
const POWERED_STABILIZATION_DURATION_MULTIPLIER := 1.30
const POWERED_STABILIZATION_VENT_COOLDOWN_MULTIPLIER := 0.80
const POWERED_STABILIZATION_SAFE_MIN := 40.0
const POWERED_STABILIZATION_SAFE_MAX := 60.0
const RAIN_CONTAMINATION_REASON := &"rain_contamination"

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
@onready var ratio_target_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/RatioTargetButton
@onready var ratio_value_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/RatioValueLabel
@onready var temperature_slider: HSlider = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/TemperatureSlider
@onready var temperature_value_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/TemperatureValueLabel
@onready var react_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/ReactButton
@onready var action_hint_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/ActionHintLabel
@onready var catalyst_visual: Panel = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/CatalystRack/MarginContainer/VBoxContainer/CatalystVisual
@onready var catalyst_name_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/CatalystRack/MarginContainer/VBoxContainer/CatalystNameLabel
@onready var close_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FooterRow/CloseButton
@onready var footer_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/FooterRow/FooterLabel
@onready var footer_row: HBoxContainer = $Root/PanelContainer/MarginContainer/VBoxContainer/FooterRow

var _chem_bench: Node = null
var _stabilization_overlay: CanvasLayer = null
var _stabilization_active := false
var _pending_result: Dictionary = {}
var _slot_refs: Dictionary[StringName, Dictionary] = {}
var _is_open := false
var _ratio_target_slot: StringName = RATIO_TARGET_INPUT_B
var _power_status_label: Label = null
var _power_button: Button = null


func _ready() -> void:
	add_to_group(&"station_inventory_drop_target")
	visible = false
	root.visible = false
	_slot_refs = {
		&"input_a": {"visual": input_a_visual, "label": input_a_name_label},
		&"input_b": {"visual": input_b_visual, "label": input_b_name_label},
		&"catalyst": {"visual": catalyst_visual, "label": catalyst_name_label},
	}
	_apply_theme()
	_ensure_power_controls()
	_refresh_from_bench()
	_update_ratio_target_button()
	_update_ratio_label(ratio_slider.value)
	_update_temperature_label(temperature_slider.value)
	ratio_target_button.pressed.connect(_on_ratio_target_button_pressed)
	ratio_slider.value_changed.connect(_on_ratio_slider_changed)
	temperature_slider.value_changed.connect(_on_temperature_slider_changed)
	react_button.pressed.connect(_on_react_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _stabilization_active:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		emit_signal("ui_closed")
		get_viewport().set_input_as_handled()


func bind_chem_bench(chem_bench: Node) -> void:
	var callback := Callable(self, "_refresh_from_bench")
	if is_instance_valid(_chem_bench) and _chem_bench.has_signal("state_changed") and _chem_bench.is_connected("state_changed", callback):
		_chem_bench.disconnect("state_changed", callback)
	_chem_bench = chem_bench
	_ensure_stabilization_overlay()
	if is_instance_valid(_chem_bench) and _chem_bench.has_signal("state_changed") and not _chem_bench.is_connected("state_changed", callback):
		_chem_bench.connect("state_changed", callback)
	_refresh_from_bench()


func open_ui() -> void:
	_is_open = true
	visible = true
	root.visible = true
	_ensure_stabilization_overlay()
	_refresh_from_bench()
	_layout_panel()
	call_deferred("_finalize_open_ui_layout")


func close_ui() -> void:
	if _stabilization_active:
		return
	_is_open = false
	root.visible = false
	visible = false


func is_open() -> bool:
	return _is_open


func can_accept_inventory_drop(global_mouse_position: Vector2, item_id: StringName, qty: int) -> bool:
	if not visible or qty <= 0 or item_id.is_empty() or not is_instance_valid(_chem_bench):
		return false

	var slot_id := _get_drop_slot_id(global_mouse_position)
	if slot_id.is_empty():
		return false

	var existing_item := StringName(_chem_bench.get_input(slot_id).get(&"item_id", &""))
	if not existing_item.is_empty() and existing_item != item_id:
		return false

	if slot_id == &"catalyst":
		return bool(_chem_bench.can_accept_catalyst(item_id))
	return bool(_chem_bench.can_accept_reactant(item_id))


func handle_inventory_drop(global_mouse_position: Vector2, item_id: StringName, qty: int) -> bool:
	if not can_accept_inventory_drop(global_mouse_position, item_id, qty):
		return false

	var slot_id := _get_drop_slot_id(global_mouse_position)
	if slot_id.is_empty():
		return false

	var accepted := bool(_chem_bench.set_input(slot_id, item_id, qty))
	if accepted:
		_refresh_from_bench()
	return accepted


func _refresh_from_bench() -> void:
	if not is_instance_valid(_chem_bench):
		return

	var state: Dictionary = _chem_bench.get_ui_state()
	_ratio_target_slot = _normalize_ratio_target_slot(StringName(state.get(&"ratio_target_slot", RATIO_TARGET_INPUT_B)))
	ratio_slider.set_value_no_signal(float(state.get(&"ratio_percent", 50.0)))
	temperature_slider.set_value_no_signal(float(state.get(&"temperature_c", 90.0)))
	_update_ratio_target_button()
	_update_ratio_label(ratio_slider.value)
	_update_temperature_label(temperature_slider.value)
	_update_power_panel(state.get(&"power_state", {}))

	for slot_id: StringName in [&"input_a", &"input_b", &"catalyst"]:
		var slot_state: Dictionary = state.get(slot_id, {})
		_apply_slot_state(slot_id, slot_state)

	_update_preview()


func _apply_slot_state(slot_id: StringName, slot_state: Dictionary) -> void:
	var refs: Dictionary = _slot_refs.get(slot_id, {})
	if refs.is_empty():
		return
	var item_id := StringName(slot_state.get(&"item_id", &""))
	var quantity := int(slot_state.get(&"quantity", 0))
	var label: Label = refs.get("label")
	var visual: Panel = refs.get("visual")
	if item_id.is_empty() or quantity <= 0:
		label.text = SLOT_EMPTY_TEXT.get(slot_id, "Empty")
		_apply_slot_panel_style(visual, SLOT_PANEL_COLOR)
		return

	label.text = "%s x%d" % [_get_item_name(item_id), quantity]
	_apply_slot_panel_style(visual, SLOT_FILLED_COLOR)


func _update_preview() -> void:
	if not is_instance_valid(_chem_bench):
		return

	var result: Dictionary = _chem_bench.evaluate_current_reaction()
	var output_id := StringName(str(result.get("output_id", "")))
	var notes := str(result.get("notes", ""))
	var preview_label := str(result.get("preview_label", ""))
	var requires_stabilization := bool(result.get("requires_stabilization", false))
	var failure_reason := StringName(str(result.get("failure_reason", "")))

	if not output_id.is_empty():
		var preview_name := "%s" % _get_item_name(output_id)
		if requires_stabilization:
			preview_name = "%s [Stabilize]" % preview_name
		output_name_label.text = preview_name
		_apply_slot_panel_style(output_visual, SLOT_OUTPUT_READY_COLOR)
	elif not failure_reason.is_empty():
		output_name_label.text = preview_label if not preview_label.is_empty() else _format_failure_label(failure_reason)
		_apply_slot_panel_style(output_visual, SLOT_OUTPUT_DANGER_COLOR)
	else:
		output_name_label.text = preview_label if not preview_label.is_empty() else SLOT_EMPTY_TEXT[&"output"]
		_apply_slot_panel_style(output_visual, SLOT_OUTPUT_UNKNOWN_COLOR)

	recipe_label.text = "Predicted Result"
	summary_label.text = notes if not notes.is_empty() else "Load two reactants and tune the bench state."
	action_hint_label.text = _build_action_hint(result)
	react_button.text = "Stabilize" if requires_stabilization else "React"
	react_button.disabled = _stabilization_active
	footer_label.text = _build_footer_copy(result)


func _build_action_hint(result: Dictionary) -> String:
	var failure_reason := StringName(str(result.get("failure_reason", "")))
	if not failure_reason.is_empty():
		return "Warning: %s" % _format_failure_label(failure_reason)
	if bool(result.get("requires_stabilization", false)):
		return "Buffered but unstable. React, then hold the stabilization window."
	if _chem_bench_has_rain_risk():
		return "Rain or wet handling can contaminate this run. Roof the bench or dry off first."
	var output_id := StringName(str(result.get("output_id", "")))
	if not output_id.is_empty():
		return "Window found. Execute now to lock in the reaction."
	return "Tune ratio, temperature, and catalyst until the bench predicts a result."


func _build_footer_copy(result: Dictionary) -> String:
	if StringName(str(result.get("output_id", ""))) == &"sulfuric_bolt":
		return "Limestone buffers sulfur chemistry. Without it, this mix vents toxic gas."
	if StringName(str(result.get("output_id", ""))) == &"rust_bolt":
		return "Controlled oxidation favors warm, wet iron without boiling off the water."
	if StringName(str(result.get("output_id", ""))) == &"corrosive_slurry":
		return "Sulfur-water slurry only holds if limestone keeps the mix from turning volatile."
	return "ChemBench outcomes depend on inputs, selected ratio target, setpoint temperature, and catalyst choice."


func _on_ratio_target_button_pressed() -> void:
	_ratio_target_slot = RATIO_TARGET_INPUT_A if _ratio_target_slot == RATIO_TARGET_INPUT_B else RATIO_TARGET_INPUT_B
	_update_ratio_target_button()
	_update_ratio_label(ratio_slider.value)
	if is_instance_valid(_chem_bench):
		_chem_bench.set_ratio_target_slot(_ratio_target_slot)
	_update_preview()


func _on_ratio_slider_changed(value: float) -> void:
	_update_ratio_label(value)
	if is_instance_valid(_chem_bench):
		_chem_bench.set_ratio_percent(value)
	_update_preview()


func _on_temperature_slider_changed(value: float) -> void:
	_update_temperature_label(value)
	if is_instance_valid(_chem_bench):
		_chem_bench.set_temperature(value)
	_update_preview()


func _on_react_button_pressed() -> void:
	if _stabilization_active or not is_instance_valid(_chem_bench):
		return

	var result: Dictionary = _chem_bench.evaluate_current_reaction()
	var output_id := StringName(str(result.get("output_id", "")))
	var failure_reason := StringName(str(result.get("failure_reason", "")))
	if output_id.is_empty() and failure_reason.is_empty():
		react_button.text = "No Reaction"
		return

	if _chem_bench != null \
		and _chem_bench.has_method("should_rain_contaminate_reaction") \
		and bool(_chem_bench.should_rain_contaminate_reaction(result)):
		result[&"failure_reason"] = _chem_bench.get_rain_failure_reason() if _chem_bench.has_method("get_rain_failure_reason") else RAIN_CONTAMINATION_REASON
		_apply_failure_result(result, StringName(result[&"failure_reason"]))
		return

	if bool(result.get("requires_stabilization", false)):
		_start_stabilization(result)
		return

	if not failure_reason.is_empty():
		_apply_failure_result(result, failure_reason)
		return

	_apply_success_result(result)


func _start_stabilization(result: Dictionary) -> void:
	_ensure_stabilization_overlay()
	if _stabilization_overlay == null:
		react_button.text = "Stabilizer Missing"
		return
	_pending_result = result.duplicate(true)
	_stabilization_active = true
	react_button.disabled = true
	close_button.disabled = true
	ratio_target_button.disabled = true
	ratio_slider.editable = false
	temperature_slider.editable = false
	action_hint_label.text = "Stabilization in progress. Player controls are locked."
	if _stabilization_overlay.has_method("start"):
		_stabilization_overlay.call(
			"start",
			_get_item_name(StringName(str(result.get("output_id", "")))),
			_get_stabilization_config()
		)


func _on_stabilization_succeeded() -> void:
	var result := _pending_result.duplicate(true)
	_finish_stabilization_state()
	if result.is_empty():
		react_button.text = "Invalid Result"
		return
	_apply_success_result(result)


func _on_stabilization_failed(reason: StringName) -> void:
	var result := _pending_result.duplicate(true)
	var inputs_log := _build_inputs_log()
	var catalyst_id := _get_catalyst_id()
	_finish_stabilization_state()
	if result.is_empty():
		return
	result[&"failure_reason"] = reason
	if _chem_bench != null and _chem_bench.has_method("trigger_stabilization_failure"):
		_chem_bench.trigger_stabilization_failure(reason)
	_consume_result_inputs(result, true)
	_log_chem_bench_result(result, false, reason, inputs_log, catalyst_id)
	output_name_label.text = _format_failure_label(reason)
	_apply_slot_panel_style(output_visual, SLOT_OUTPUT_DANGER_COLOR)
	react_button.text = "Reaction Failed"
	action_hint_label.text = _format_failure_label(reason)
	_refresh_from_bench()


func _finish_stabilization_state() -> void:
	_stabilization_active = false
	react_button.disabled = false
	close_button.disabled = false
	ratio_target_button.disabled = false
	ratio_slider.editable = true
	temperature_slider.editable = true
	_pending_result = {}


func _apply_success_result(result: Dictionary) -> void:
	var output_id := StringName(str(result.get("output_id", "")))
	var output_quantity := int(result.get(&"output_qty", 1))
	var output_item := _build_output_item(output_id)
	var inputs_log := _build_inputs_log()
	var catalyst_id := _get_catalyst_id()
	if output_item.is_empty() or output_quantity <= 0:
		react_button.text = "Invalid Output"
		return
	if not InventoryManager.can_add_item(output_item, output_quantity):
		react_button.text = "Inventory Full"
		return

	_consume_result_inputs(result, false)
	if not InventoryManager.add_item(output_item, output_quantity):
		react_button.text = "Inventory Full"
		return

	_log_chem_bench_result(result, true, &"", inputs_log, catalyst_id)
	if bool(result.get("requires_stabilization", false)) and DiscoveryLog != null and DiscoveryLog.has_method("log_progression_discovery"):
		DiscoveryLog.log_progression_discovery(
			STABILIZATION_DISCOVERY_ID,
			"Stabilization Theory",
			"First live stabilization achieved. Buffered sulfur chemistry can now be identified in recipe references."
		)
	output_name_label.text = "%s x%d" % [_get_item_name(output_id), output_quantity]
	_apply_slot_panel_style(output_visual, SLOT_OUTPUT_READY_COLOR)
	react_button.text = "%s Crafted" % _get_item_name(output_id)
	_refresh_from_bench()


func _apply_failure_result(result: Dictionary, failure_reason: StringName) -> void:
	var inputs_log := _build_inputs_log()
	var catalyst_id := _get_catalyst_id()
	_consume_result_inputs(result, true)
	if _chem_bench != null and _chem_bench.has_method("trigger_stabilization_failure"):
		_chem_bench.trigger_stabilization_failure(failure_reason)
	_log_chem_bench_result(result, false, failure_reason, inputs_log, catalyst_id)
	output_name_label.text = _format_failure_label(failure_reason)
	_apply_slot_panel_style(output_visual, SLOT_OUTPUT_DANGER_COLOR)
	react_button.text = "Reaction Failed"
	action_hint_label.text = _format_failure_label(failure_reason)
	_refresh_from_bench()


func _consume_result_inputs(result: Dictionary, include_failure_consumption: bool) -> void:
	if not is_instance_valid(_chem_bench):
		return
	for consume_data: Dictionary in result.get(&"consumed_inputs", []):
		var slot_id := StringName(consume_data.get(&"slot_id", &""))
		var quantity := int(consume_data.get(&"quantity", 0))
		if quantity > 0:
			_chem_bench.consume_input(slot_id, quantity)
	if include_failure_consumption or bool(result.get(&"consume_catalyst_on_success", false)):
		var catalyst_quantity := int(result.get(&"consumed_catalyst", 0))
		if catalyst_quantity > 0:
			_chem_bench.consume_input(&"catalyst", catalyst_quantity)


func _log_chem_bench_result(result: Dictionary, discover_output: bool, failure_reason: StringName = &"", inputs_log: Array = [], catalyst_id: StringName = &"") -> void:
	if not DiscoveryLog.has_method("log_chemistry") or not is_instance_valid(_chem_bench):
		return

	var output_id := StringName(str(result.get("output_id", "")))
	var output_quantity := int(result.get(&"output_qty", 1))
	var output_name := ""
	if discover_output and not output_id.is_empty():
		output_name = "%s x%d" % [_get_item_name(output_id), output_quantity]
	var ratio_percent := int(round(_chem_bench.get_ratio_percent()))
	var ratio_target_slot := _normalize_ratio_target_slot(StringName(_chem_bench.get_ratio_target_slot()))
	var ratio_target_label := "Input A" if ratio_target_slot == RATIO_TARGET_INPUT_A else "Input B"
	var temperature_c := int(round(_chem_bench.get_temperature()))
	var catalyst_name := _get_item_name(catalyst_id) if not catalyst_id.is_empty() else "none"
	var conditions_summary := "Bench run at %d°C with %s ratio %d%% and catalyst %s. %s" % [
		temperature_c,
		ratio_target_label,
		ratio_percent,
		catalyst_name,
		str(result.get("notes", "")),
	]
	if not failure_reason.is_empty():
		conditions_summary = "%s Failure: %s." % [conditions_summary, _format_failure_label(failure_reason)]

	var result_for_log := result.duplicate(true)
	result_for_log[&"notes"] = conditions_summary
	DiscoveryLog.log_chemistry(
		result_for_log,
		inputs_log,
		conditions_summary,
		output_name,
		discover_output
	)


func _build_inputs_log() -> Array:
	var inputs_log: Array = []
	if not is_instance_valid(_chem_bench):
		return inputs_log
	for slot_id: StringName in [&"input_a", &"input_b", &"catalyst"]:
		var slot_state: Dictionary = _chem_bench.get_input(slot_id)
		var item_id := StringName(slot_state.get(&"item_id", &""))
		var quantity := int(slot_state.get(&"quantity", 0))
		if item_id.is_empty() or quantity <= 0:
			continue
		inputs_log.append({
			"item_id": item_id,
			"quantity": quantity,
		})
	return inputs_log


func _get_catalyst_id() -> StringName:
	if not is_instance_valid(_chem_bench):
		return &""
	return StringName(_chem_bench.get_input(&"catalyst").get(&"item_id", &""))


func _build_output_item(output_id: StringName) -> Dictionary:
	if output_id.is_empty():
		return {}

	var item_data := {
		&"id": output_id,
		&"display_name": _get_item_name(output_id),
		&"category": InventoryManager.InventoryItemCategory.CONSUMABLE,
	}
	if output_id == &"rust_bolt":
		item_data[&"weapon_type"] = "ranged"
		item_data[&"projectile_id"] = "rust_bolt"
		item_data[&"damage_type"] = "oxidation"
		item_data[&"base_damage"] = 15.0
	elif output_id == &"sulfuric_bolt":
		item_data[&"weapon_type"] = "ranged"
		item_data[&"projectile_id"] = "sulfuric_bolt"
		item_data[&"damage_type"] = "chemical"
		item_data[&"base_damage"] = 22.0
	elif output_id == &"corrosive_slurry":
		item_data[&"mixture_type"] = "corrosive_slurry"
	return item_data


func _format_failure_label(reason: StringName) -> String:
	match reason:
		RAIN_CONTAMINATION_REASON:
			return "Failure: rain contamination"
		&"heat_runaway":
			return "Failure: heat runaway"
		&"pressure_spike":
			return "Failure: pressure spike"
		&"timer_expiry":
			return "Failure: toxic release"
		_:
			return "Failure: unstable reaction"


func _ensure_stabilization_overlay() -> void:
	if _stabilization_overlay != null:
		return
	_stabilization_overlay = STABILIZATION_MINIGAME_SCENE.instantiate()
	add_child(_stabilization_overlay)
	if _stabilization_overlay.has_signal("stabilization_succeeded"):
		_stabilization_overlay.stabilization_succeeded.connect(_on_stabilization_succeeded)
	if _stabilization_overlay.has_signal("stabilization_failed"):
		_stabilization_overlay.stabilization_failed.connect(_on_stabilization_failed)


func _ensure_power_controls() -> void:
	if _power_status_label != null and _power_button != null:
		return
	var power_column := VBoxContainer.new()
	power_column.name = "PowerColumn"
	power_column.alignment = BoxContainer.ALIGNMENT_CENTER
	power_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	power_column.custom_minimum_size = Vector2(170.0, 0.0)

	_power_status_label = Label.new()
	_power_status_label.name = "PowerStatusLabel"
	_power_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_power_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_column.add_child(_power_status_label)

	_power_button = Button.new()
	_power_button.name = "PowerButton"
	_power_button.text = "Insert Energy Cell"
	_power_button.pressed.connect(_on_power_button_pressed)
	power_column.add_child(_power_button)

	footer_row.add_child(power_column)
	footer_row.move_child(power_column, 1)


func _update_power_panel(power_state: Dictionary) -> void:
	if _power_status_label == null or _power_button == null:
		return
	var switchboard_enabled := bool(power_state.get(&"switchboard_enabled", true))
	var boost_active := bool(power_state.get(&"boost_active", false))
	var grid_powered := bool(power_state.get(&"grid_powered", false))
	if boost_active and switchboard_enabled:
		_power_status_label.text = "Grid boost active\nStabilization gets wider pressure margins and faster vent recovery."
	elif not switchboard_enabled:
		_power_status_label.text = "Bench boost disabled at the battery station switchboard."
	elif not grid_powered:
		_power_status_label.text = "Boost available through the battery station.\nCharge the defense grid to enable it."
	else:
		_power_status_label.text = "Boost is managed by the battery station switchboard."
	_power_button.text = "Managed at Battery Station"
	_power_button.disabled = true


func _on_power_button_pressed() -> void:
	return


func _get_stabilization_config() -> Dictionary:
	if not is_instance_valid(_chem_bench):
		return {}
	var config := {}
	var duration_multiplier := 1.0
	if _chem_bench.has_method("has_power_bonus") and _chem_bench.has_power_bonus():
		duration_multiplier *= POWERED_STABILIZATION_DURATION_MULTIPLIER
		config[&"pressure_safe_min"] = POWERED_STABILIZATION_SAFE_MIN
		config[&"pressure_safe_max"] = POWERED_STABILIZATION_SAFE_MAX
		config[&"vent_cooldown_seconds"] = 2.0 * POWERED_STABILIZATION_VENT_COOLDOWN_MULTIPLIER
	if _chem_bench.has_method("get_rain_slowdown_multiplier"):
		duration_multiplier *= float(_chem_bench.get_rain_slowdown_multiplier())
	if not is_equal_approx(duration_multiplier, 1.0):
		config[&"reaction_duration_seconds"] = 10.0 * duration_multiplier
	return config


func _chem_bench_has_rain_risk() -> bool:
	return _chem_bench != null \
		and _chem_bench.has_method("has_rain_condition_risk") \
		and bool(_chem_bench.has_rain_condition_risk())


func _on_close_button_pressed() -> void:
	if _stabilization_active:
		return
	emit_signal("ui_closed")


func _layout_panel() -> void:
	if panel == null:
		return

	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.pivot_offset = Vector2.ZERO
	panel.size = panel.custom_minimum_size
	panel.scale = Vector2(PANEL_VIEW_SCALE, PANEL_VIEW_SCALE)

	var viewport_size := get_viewport().get_visible_rect().size
	var scaled_size := panel.size * PANEL_VIEW_SCALE
	panel.position = Vector2(
		PANEL_MARGIN.x,
		maxf(PANEL_MARGIN.y, (viewport_size.y - scaled_size.y) * 0.5)
	)


func _finalize_open_ui_layout() -> void:
	if not _is_open or panel == null:
		return
	_layout_panel()
	panel.scale = Vector2(PANEL_VIEW_SCALE, PANEL_VIEW_SCALE)


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
	temperature_value_label.add_theme_color_override("font_color", Color(0.83, 0.77, 0.69, 1.0))

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


func _update_ratio_label(value: float) -> void:
	var target_label := "Input A" if _ratio_target_slot == RATIO_TARGET_INPUT_A else "Input B"
	ratio_value_label.text = "%s Ratio: %d%%" % [target_label, int(round(value))]


func _update_ratio_target_button() -> void:
	ratio_target_button.text = "Target: %s" % ("Input A" if _ratio_target_slot == RATIO_TARGET_INPUT_A else "Input B")


func _update_temperature_label(value: float) -> void:
	var clamped := clampf(value, TEMPERATURE_MIN, TEMPERATURE_MAX)
	temperature_value_label.text = "Setpoint: %d°C" % int(round(clamped))


func _normalize_ratio_target_slot(slot_id: StringName) -> StringName:
	if slot_id == RATIO_TARGET_INPUT_A:
		return RATIO_TARGET_INPUT_A
	return RATIO_TARGET_INPUT_B


func _get_drop_slot_id(global_mouse_position: Vector2) -> StringName:
	for slot_id: StringName in [&"input_a", &"input_b", &"catalyst"]:
		var refs: Dictionary = _slot_refs.get(slot_id, {})
		var visual: Panel = refs.get("visual")
		if visual != null and visual.get_global_rect().has_point(global_mouse_position):
			return slot_id
	return &""


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


func _get_item_name(item_id: StringName) -> String:
	if item_id.is_empty():
		return "Unknown"
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", String(item_id)))
	return String(item_id).replace("_", " ").capitalize()
