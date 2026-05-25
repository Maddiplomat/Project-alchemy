extends CanvasLayer

signal ui_closed

const STABILIZATION_MINIGAME_SCENE := preload("res://scenes/UI/StabilizationMinigame.tscn")
const SLOT_EMPTY_TEXT := {
	&"input_a": "Input A",
	&"input_b": "Input B",
	&"output": "Output",
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
@onready var action_hint_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/ActionHintLabel
@onready var close_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FooterRow/CloseButton

var _chem_bench: Node = null
var _bench_recipes: Array[Dictionary] = []
var _active_recipe: Dictionary = {}
var _stabilization_overlay: CanvasLayer = null
var _stabilization_active := false
var _pending_output_item: Dictionary = {}
var _pending_output_quantity := 0
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
	if _stabilization_active:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		emit_signal("ui_closed")
		get_viewport().set_input_as_handled()


func bind_chem_bench(chem_bench: Node) -> void:
	_chem_bench = chem_bench
	_ensure_stabilization_overlay()
	if _chem_bench != null and _chem_bench.has_method("get_available_recipes"):
		_bench_recipes = _chem_bench.get_available_recipes()
	elif _chem_bench != null and _chem_bench.has_method("get_active_recipe"):
		var fallback_recipe: Dictionary = _chem_bench.get_active_recipe()
		_bench_recipes = [fallback_recipe] if not fallback_recipe.is_empty() else []
	_sync_active_recipe()
	_refresh_recipe_copy()
	_refresh_slot_visuals()


func open_ui() -> void:
	visible = true
	root.visible = true
	_ensure_stabilization_overlay()


func close_ui() -> void:
	if _stabilization_active:
		return
	root.visible = false
	visible = false


func _on_ratio_slider_changed(value: float) -> void:
	_update_ratio_label(value)


func _on_react_button_pressed() -> void:
	if _stabilization_active:
		return
	if not _can_craft_active_recipe():
		react_button.text = _get_missing_materials_text()
		return

	var output_item := _build_output_item()
	var output_quantity := int(_active_recipe.get(&"output", {}).get(&"qty", 0))
	if output_item.is_empty() or output_quantity <= 0:
		react_button.text = "Invalid Recipe"
		return
	if not InventoryManager.can_add_item(output_item, output_quantity):
		react_button.text = "Inventory Full"
		return

	if bool(_active_recipe.get(&"requires_stabilization", false)):
		_start_stabilization(output_item, output_quantity)
		return

	if not InventoryManager.add_item(output_item, output_quantity):
		react_button.text = "Inventory Full"
		return

	_complete_reaction_success(output_item, output_quantity)


func _complete_reaction_success(output_item: Dictionary, output_quantity: int) -> void:
	_clear_inputs()
	output_name_label.text = "%s x%d" % [str(output_item.get(&"display_name", "Output")), output_quantity]
	_apply_slot_panel_style(output_visual, SLOT_OUTPUT_READY_COLOR)
	react_button.text = "%s Crafted" % str(output_item.get(&"display_name", "Item"))


func _start_stabilization(output_item: Dictionary, output_quantity: int) -> void:
	_ensure_stabilization_overlay()
	if _stabilization_overlay == null:
		react_button.text = "Stabilizer Missing"
		return
	_pending_output_item = output_item.duplicate(true)
	_pending_output_quantity = output_quantity
	_stabilization_active = true
	react_button.disabled = true
	close_button.disabled = true
	ratio_slider.editable = false
	action_hint_label.text = "Stabilization in progress. Player controls are locked."
	var recipe_name := str(_active_recipe.get(&"display_name", "Reaction"))
	if _stabilization_overlay.has_method("start"):
		_stabilization_overlay.call("start", recipe_name)


func _finish_stabilization_state() -> void:
	_stabilization_active = false
	react_button.disabled = false
	close_button.disabled = false
	ratio_slider.editable = true
	_pending_output_item = {}
	_pending_output_quantity = 0
	_refresh_recipe_copy()


func _on_stabilization_succeeded() -> void:
	var output_item := _pending_output_item.duplicate(true)
	var output_quantity := _pending_output_quantity
	_finish_stabilization_state()
	if output_item.is_empty() or output_quantity <= 0:
		react_button.text = "Invalid Recipe"
		return
	if not InventoryManager.add_item(output_item, output_quantity):
		react_button.text = "Inventory Full"
		return
	_complete_reaction_success(output_item, output_quantity)


func _on_stabilization_failed(reason: StringName) -> void:
	_finish_stabilization_state()
	if _chem_bench != null and _chem_bench.has_method("trigger_stabilization_failure"):
		_chem_bench.trigger_stabilization_failure(reason)
	_clear_inputs()
	output_name_label.text = _format_stabilization_failure(reason)
	_apply_slot_panel_style(output_visual, Color(0.42, 0.13, 0.10, 1.0))
	react_button.text = "Reaction Failed"
	action_hint_label.text = _format_stabilization_failure(reason)


func _ensure_stabilization_overlay() -> void:
	if _stabilization_overlay != null:
		return
	_stabilization_overlay = STABILIZATION_MINIGAME_SCENE.instantiate()
	add_child(_stabilization_overlay)
	if _stabilization_overlay.has_signal("stabilization_succeeded"):
		_stabilization_overlay.stabilization_succeeded.connect(_on_stabilization_succeeded)
	if _stabilization_overlay.has_signal("stabilization_failed"):
		_stabilization_overlay.stabilization_failed.connect(_on_stabilization_failed)


func _format_stabilization_failure(reason: StringName) -> String:
	match reason:
		&"heat_runaway":
			return "Failure: heat runaway"
		&"pressure_spike":
			return "Failure: pressure spike"
		&"timer_expiry":
			return "Failure: toxic release"
		_:
			return "Failure: unstable reaction"


func _on_close_button_pressed() -> void:
	if _stabilization_active:
		return
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

	var existing_qty := int(_slot_state[slot_id].get(&"quantity", 0)) if _slot_state[slot_id].get(&"item_id", &"") == item_id or _slot_state[slot_id].get(&"item_id", &"").is_empty() else 0
	_slot_state[slot_id] = {
		&"item_id": item_id,
		&"quantity": existing_qty + qty,
	}
	_sync_active_recipe()
	_refresh_recipe_copy()
	_refresh_slot_visuals()
	react_button.text = _get_action_verb()
	return true


func _update_ratio_label(value: float) -> void:
	ratio_value_label.text = "Bench Ratio: %.0f / %.0f" % [value, ratio_slider.max_value]


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

	var existing: Dictionary = _slot_state.get(slot_id, {})
	var current_item_id: StringName = existing.get(&"item_id", &"")
	if not current_item_id.is_empty() and current_item_id != item_id:
		return false

	var test_state := _slot_state.duplicate(true)
	var existing_qty := int(existing.get(&"quantity", 0))
	test_state[slot_id] = {
		&"item_id": item_id,
		&"quantity": existing_qty + qty,
	}
	return not _get_matching_recipes(test_state, false).is_empty()


func _can_craft_active_recipe() -> bool:
	return not _active_recipe.is_empty() and _recipe_matches_state(_active_recipe, _slot_state, true)


func _clear_inputs() -> void:
	_slot_state[&"input_a"] = {&"item_id": &"", &"quantity": 0}
	_slot_state[&"input_b"] = {&"item_id": &"", &"quantity": 0}
	_sync_active_recipe()
	_refresh_recipe_copy()
	_refresh_slot_visuals()
	react_button.text = _get_action_verb()


func _refresh_slot_visuals() -> void:
	_apply_slot_state(&"input_a", input_a_name_label, input_a_visual)
	_apply_slot_state(&"input_b", input_b_name_label, input_b_visual)
	if not _can_craft_active_recipe():
		output_name_label.text = _get_output_placeholder_text()
		_apply_slot_panel_style(output_visual, SLOT_PANEL_COLOR)


func _apply_slot_state(slot_id: StringName, label: Label, visual: Panel) -> void:
	var slot_state: Dictionary = _slot_state.get(slot_id, {})
	var item_id: StringName = slot_state.get(&"item_id", &"")
	var quantity := int(slot_state.get(&"quantity", 0))
	if item_id.is_empty() or quantity <= 0:
		label.text = _get_input_placeholder_text(slot_id)
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


func _get_recipe_input_for_slot(slot_id: StringName) -> Dictionary:
	var inputs: Array = _active_recipe.get(&"inputs", [])
	var input_index := 0 if slot_id == &"input_a" else 1
	if input_index < 0 or input_index >= inputs.size():
		return {}
	return inputs[input_index]


func _get_input_placeholder_text(slot_id: StringName) -> String:
	var input_data := _get_recipe_input_for_slot(slot_id)
	if input_data.is_empty():
		return SLOT_EMPTY_TEXT[slot_id]
	return _get_item_name(input_data.get(&"element_id", &""))


func _get_output_placeholder_text() -> String:
	var output: Dictionary = _active_recipe.get(&"output", {})
	var output_id: StringName = output.get(&"item_id", &"")
	if output_id.is_empty():
		return SLOT_EMPTY_TEXT[&"output"]
	return _get_item_name(output_id)


func _get_missing_materials_text() -> String:
	var parts: Array[String] = []
	for input_data: Dictionary in _active_recipe.get(&"inputs", []):
		parts.append("%d %s" % [
			int(input_data.get(&"qty", 0)),
			_get_item_name(input_data.get(&"element_id", &"")),
		])
	return "Need %s" % " + ".join(parts)


func _build_output_item() -> Dictionary:
	var output: Dictionary = _active_recipe.get(&"output", {})
	var output_id: StringName = output.get(&"item_id", &"")
	if output_id.is_empty():
		return {}

	var category := InventoryManager.InventoryItemCategory.CRAFTED
	if output_id == &"distillation_kit":
		category = InventoryManager.InventoryItemCategory.TOOL
	if _active_recipe.get(&"durability") == null:
		category = InventoryManager.InventoryItemCategory.CONSUMABLE

	var item_data := {
		&"id": output_id,
		&"display_name": _get_item_name(output_id),
		&"category": category,
	}
	var durability = _active_recipe.get(&"durability")
	if durability != null:
		var normalized_durability := clampf(float(durability), 0.0, 1.0)
		item_data[&"durability"] = normalized_durability
		item_data[&"max_durability"] = normalized_durability
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
		item_data[&"requires_stabilization"] = bool(_active_recipe.get(&"requires_stabilization", false))
	elif output_id == &"distillation_kit":
		item_data[&"tool_type"] = "distillation_kit"
	return item_data


func _get_action_verb() -> String:
	var reaction_type := String(_active_recipe.get(&"reaction_type", "")).to_lower()
	match reaction_type:
		"forging":
			return "Forge"
		_:
			return "React"


func _sync_active_recipe() -> void:
	var exact_matches := _get_matching_recipes(_slot_state, true)
	if exact_matches.size() == 1:
		_active_recipe = exact_matches[0]
		return

	var partial_matches := _get_matching_recipes(_slot_state, false)
	if partial_matches.size() == 1:
		_active_recipe = partial_matches[0]
		return

	_active_recipe = {}


func _refresh_recipe_copy() -> void:
	if _active_recipe.is_empty():
		recipe_label.text = "ACTIVE RECIPE: Awaiting Valid Inputs"
		summary_label.text = "Load a matching material pair to reveal the bench recipe."
		action_hint_label.text = _get_supported_recipe_hint()
		react_button.text = "React"
		return

	var recipe_name := str(_active_recipe.get(&"display_name", "Unknown Recipe"))
	recipe_label.text = "ACTIVE RECIPE: %s" % recipe_name
	summary_label.text = str(_active_recipe.get(&"summary", ""))
	action_hint_label.text = (
		"Load both required materials, stabilize the reaction, then %s." % _get_action_verb().to_lower()
		if bool(_active_recipe.get(&"requires_stabilization", false)) else
		"Load both required materials, then %s." % _get_action_verb().to_lower()
	)
	react_button.text = _get_action_verb()


func _get_matching_recipes(slot_state: Dictionary, require_exact_quantities: bool) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for recipe: Dictionary in _bench_recipes:
		if _recipe_matches_state(recipe, slot_state, require_exact_quantities):
			matches.append(recipe)
	return matches


func _recipe_matches_state(recipe: Dictionary, slot_state: Dictionary, require_exact_quantities: bool) -> bool:
	var inputs: Array = recipe.get(&"inputs", [])
	if inputs.size() < 2:
		return false

	var a_input: Dictionary = slot_state.get(&"input_a", {})
	var b_input: Dictionary = slot_state.get(&"input_b", {})
	var a_id: StringName = a_input.get(&"item_id", &"")
	var a_qty := int(a_input.get(&"quantity", 0))
	var b_id: StringName = b_input.get(&"item_id", &"")
	var b_qty := int(b_input.get(&"quantity", 0))

	var exp0_id: StringName = inputs[0].get(&"element_id", &"")
	var exp0_qty := int(inputs[0].get(&"qty", 0))
	var exp1_id: StringName = inputs[1].get(&"element_id", &"")
	var exp1_qty := int(inputs[1].get(&"qty", 0))

	var match_straight := _check_pair(a_id, a_qty, b_id, b_qty, exp0_id, exp0_qty, exp1_id, exp1_qty, require_exact_quantities)
	var match_swapped := _check_pair(a_id, a_qty, b_id, b_qty, exp1_id, exp1_qty, exp0_id, exp0_qty, require_exact_quantities)
	
	return match_straight or match_swapped


func _check_pair(act1_id: StringName, act1_qty: int, act2_id: StringName, act2_qty: int, exp1_id: StringName, exp1_qty: int, exp2_id: StringName, exp2_qty: int, req_exact: bool) -> bool:
	if not _check_single(act1_id, act1_qty, exp1_id, exp1_qty, req_exact):
		return false
	if not _check_single(act2_id, act2_qty, exp2_id, exp2_qty, req_exact):
		return false
	return true


func _check_single(act_id: StringName, act_qty: int, exp_id: StringName, exp_qty: int, req_exact: bool) -> bool:
	if act_id.is_empty() or act_qty <= 0:
		return not req_exact
	if act_id != exp_id:
		return false
	if req_exact:
		return act_qty == exp_qty
	return act_qty <= exp_qty


func _get_supported_recipe_hint() -> String:
	var pair_labels: Array[String] = []
	for recipe: Dictionary in _bench_recipes:
		var inputs: Array = recipe.get(&"inputs", [])
		if inputs.size() < 2:
			continue
		pair_labels.append("%s + %s" % [
			_get_item_name(inputs[0].get(&"element_id", &"")),
			_get_item_name(inputs[1].get(&"element_id", &"")),
		])
	if pair_labels.is_empty():
		return "Load a matching material pair."
	return "Supported pairs: %s." % ", or ".join(pair_labels)
