class_name FurnacePrediction
extends RefCounted

const RATIO_GUIDE_TOOLTIP_FALLBACK := "Load a carbon source into Input B for steel guidance."
const STEEL_SWORD_RECIPE_INPUT := &"steel"
const STEEL_SWORD_RECIPE_OUTPUT := &"steel_sword"
const TOOL_RECIPE_DEFINITIONS := {
	&"iron_axe": {
		&"metal_id": &"iron",
		&"metal_qty": 2,
		&"wood_qty": 2,
		&"display_name": "Iron Axe",
		&"tool_type": "axe",
	},
	&"steel_axe": {
		&"metal_id": &"steel",
		&"metal_qty": 2,
		&"wood_qty": 2,
		&"display_name": "Steel Axe",
		&"tool_type": "axe",
		&"discovery_gate": {
			&"entry_id": &"steel",
			&"hint": "Discover Steel in the furnace to unlock advanced forge patterns.",
			&"locked_name": "???",
		},
	},
	&"iron_pickaxe": {
		&"metal_id": &"iron",
		&"metal_qty": 2,
		&"wood_qty": 2,
		&"display_name": "Iron Pickaxe",
		&"tool_type": "pickaxe",
	},
	&"steel_pickaxe": {
		&"metal_id": &"steel",
		&"metal_qty": 2,
		&"wood_qty": 2,
		&"display_name": "Steel Pickaxe",
		&"tool_type": "pickaxe",
		&"discovery_gate": {
			&"entry_id": &"steel",
			&"hint": "Discover Steel in the furnace to unlock advanced forge patterns.",
			&"locked_name": "???",
		},
	},
}


func get_matching_tool_recipe_output_ids(slot_state: Dictionary, include_locked: bool, is_recipe_unlocked: Callable) -> Array[StringName]:
	var input_a: Dictionary = slot_state.get(&"input_a", {})
	var input_b: Dictionary = slot_state.get(&"input_b", {})
	var input_a_id: StringName = input_a.get(&"item_id", &"")
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	var matches: Array[StringName] = []

	for output_id: StringName in TOOL_RECIPE_DEFINITIONS.keys():
		var recipe: Dictionary = TOOL_RECIPE_DEFINITIONS[output_id]
		var metal_id: StringName = recipe.get(&"metal_id", &"")
		var metal_qty := int(recipe.get(&"metal_qty", 0))
		var wood_qty := int(recipe.get(&"wood_qty", 0))
		var matches_straight := (
			input_a_id == metal_id and input_a_qty >= metal_qty and
			input_b_id == &"wood" and input_b_qty >= wood_qty
		)
		var matches_swapped := (
			input_b_id == metal_id and input_b_qty >= metal_qty and
			input_a_id == &"wood" and input_a_qty >= wood_qty
		)
		if not (matches_straight or matches_swapped):
			continue
		if include_locked and not _is_recipe_unlocked(recipe, is_recipe_unlocked):
			matches.append(output_id)
			continue
		if not include_locked and not _is_recipe_unlocked(recipe, is_recipe_unlocked):
			continue
		matches.append(output_id)
	return matches


func get_matching_forge_output_ids(slot_state: Dictionary, include_locked: bool, is_recipe_unlocked: Callable) -> Array[StringName]:
	var forge_outputs := get_matching_tool_recipe_output_ids(slot_state, include_locked, is_recipe_unlocked)
	if is_steel_sword_forge_ready(slot_state) and (include_locked or is_steel_sword_unlocked(is_recipe_unlocked)):
		forge_outputs.append(STEEL_SWORD_RECIPE_OUTPUT)
	return forge_outputs


func sync_forge_selection(slot_state: Dictionary, available_forge_output_ids: Array[StringName], selected_forge_output_index: int, is_recipe_unlocked: Callable) -> Dictionary:
	var forge_outputs := get_matching_forge_output_ids(slot_state, false, is_recipe_unlocked)
	var previous_selection: StringName = &""
	if not available_forge_output_ids.is_empty() and selected_forge_output_index < available_forge_output_ids.size():
		previous_selection = available_forge_output_ids[selected_forge_output_index]
	if forge_outputs.is_empty():
		return {
			&"available_forge_output_ids": forge_outputs,
			&"selected_forge_output_index": 0,
			&"selected_output_id": StringName(&""),
		}

	var next_index := clampi(selected_forge_output_index, 0, forge_outputs.size() - 1)
	if not previous_selection.is_empty():
		var selected_index := forge_outputs.find(previous_selection)
		if selected_index != -1:
			next_index = selected_index

	return {
		&"available_forge_output_ids": forge_outputs,
		&"selected_forge_output_index": next_index,
		&"selected_output_id": forge_outputs[next_index],
	}


func build_output_preview(slot_state: Dictionary, current_temp: float, carbonisation_mode: bool, ratio_value: float, available_forge_output_ids: Array[StringName], selected_forge_output_index: int, charred_output_id: StringName, element_resolver: Callable, item_label_resolver: Callable, forge_lock_hint_resolver: Callable, is_recipe_unlocked: Callable, reaction_evaluator: Callable = Callable()) -> Dictionary:
	var selection := sync_forge_selection(slot_state, available_forge_output_ids, selected_forge_output_index, is_recipe_unlocked)
	var selected_output_id: StringName = selection.get(&"selected_output_id", &"")
	var input_a: Dictionary = slot_state.get(&"input_a", {})
	var input_b: Dictionary = slot_state.get(&"input_b", {})
	var input_a_id: StringName = input_a.get(&"item_id", &"")
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))

	var base_result := selection.duplicate(true)
	if input_a_qty <= 0 and input_b_qty <= 0:
		base_result[&"kind"] = "placeholder"
		base_result[&"placeholder_text"] = "Awaiting recipe"
		return base_result

	if not selected_output_id.is_empty():
		base_result[&"kind"] = "output"
		base_result[&"output_id"] = selected_output_id
		base_result[&"quantity"] = 1
		var forge_outputs: Array[StringName] = selection.get(&"available_forge_output_ids", [])
		if forge_outputs.size() > 1:
			base_result[&"action_hint"] = "Use Forge for %s. Cycle recipe to choose (%d/%d)." % [
				item_label_resolver.call(selected_output_id),
				int(selection.get(&"selected_forge_output_index", 0)) + 1,
				forge_outputs.size(),
			]
		else:
			base_result[&"action_hint"] = "Use Forge for %s." % item_label_resolver.call(selected_output_id)
		return base_result

	var locked_forge_outputs := get_matching_forge_output_ids(slot_state, true, is_recipe_unlocked)
	if not locked_forge_outputs.is_empty():
		base_result[&"kind"] = "placeholder"
		base_result[&"placeholder_text"] = "Discovery locked"
		base_result[&"action_hint"] = forge_lock_hint_resolver.call(locked_forge_outputs[0])
		return base_result

	if input_b_qty <= 0 and input_a_id == &"wood":
		base_result[&"kind"] = "output"
		base_result[&"output_id"] = charred_output_id
		base_result[&"quantity"] = maxi(1, input_a_qty)
		return base_result

	if input_a_qty <= 0 and input_b_id == &"wood":
		base_result[&"kind"] = "output"
		base_result[&"output_id"] = charred_output_id
		base_result[&"quantity"] = maxi(1, input_b_qty)
		return base_result

	if carbonisation_mode:
		base_result[&"kind"] = "placeholder"
		base_result[&"placeholder_text"] = "Awaiting heat"
		return base_result

	if input_a_qty <= 0 or input_b_qty <= 0:
		base_result[&"kind"] = "placeholder"
		base_result[&"placeholder_text"] = "Load two materials"
		return base_result

	var source_info := get_active_carbon_source_info(slot_state, carbonisation_mode, element_resolver)
	var prediction := evaluate_alloy_prediction(input_a_id, input_b_id, current_temp, ratio_value, source_info, reaction_evaluator)
	base_result[&"kind"] = "prediction"
	base_result[&"prediction"] = prediction
	return base_result


func get_active_carbon_source_info(slot_state: Dictionary, carbonisation_mode: bool, element_resolver: Callable) -> Dictionary:
	if carbonisation_mode:
		return {}

	var input_b: Dictionary = slot_state.get(&"input_b", {})
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	if input_b_id.is_empty():
		return {}

	var element_data: Dictionary = element_resolver.call(input_b_id)
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


func get_effective_b_ratio(ratio_value: float, source_info: Dictionary) -> float:
	var carbon_fraction := clampf(float(source_info.get("carbon_fraction", 0.0)), 0.0, 1.0)
	if carbon_fraction <= 0.0:
		return 0.0
	return clampf(ratio_value / carbon_fraction, 0.0, 100.0)


func get_active_ratio_guidance(carbonisation_mode: bool, source_info: Dictionary) -> Dictionary:
	if carbonisation_mode:
		return {
			"has_window": false,
			"tooltip": "Carbonisation mode: a single Wood stack is loaded."
		}
	if source_info.is_empty():
		return {
			"has_window": false,
			"tooltip": RATIO_GUIDE_TOOLTIP_FALLBACK
		}
	return build_ratio_guidance(source_info)


func build_ratio_guidance(source_info: Dictionary) -> Dictionary:
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
			format_pct(steel_window_min),
			format_pct(steel_window_max)
		]
	}


func format_pct(value: float) -> String:
	var rounded_value := snappedf(value, 0.1)
	if is_equal_approx(rounded_value, roundf(rounded_value)):
		return str(int(round(rounded_value)))
	return "%.1f" % rounded_value


func evaluate_alloy_prediction(input_a_id: StringName, input_b_id: StringName, current_temp: float, ratio_value: float, source_info: Dictionary, reaction_evaluator: Callable = Callable()) -> Dictionary:
	if source_info.is_empty():
		return {
			"output_id": null,
			"quality": 0.0,
			"tier": "unknown",
			"notes": "No carbon source profile"
		}

	var evaluator := reaction_evaluator
	if not evaluator.is_valid():
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			var chemistry_engine := (main_loop as SceneTree).root.get_node_or_null("/root/ChemistryEngine")
			if chemistry_engine != null and chemistry_engine.has_method("evaluate_reaction"):
				evaluator = Callable(chemistry_engine, "evaluate_reaction")
	if not evaluator.is_valid():
		return {
			"output_id": null,
			"quality": 0.0,
			"tier": "unknown",
			"notes": "Chemistry evaluator unavailable"
		}

	return evaluator.call(
		String(input_a_id),
		String(input_b_id),
		get_effective_b_ratio(ratio_value, source_info),
		current_temp
	)


func build_tool_item(output_id: StringName, tool_category: int) -> Dictionary:
	var recipe: Dictionary = TOOL_RECIPE_DEFINITIONS.get(output_id, {})
	return {
		&"id": output_id,
		&"display_name": str(recipe.get(&"display_name", String(output_id).replace("_", " ").capitalize())),
		&"category": tool_category,
		&"durability": 1.0,
		&"max_durability": 1.0,
		&"tool_type": str(recipe.get(&"tool_type", "")),
	}


func is_steel_sword_forge_ready(slot_state: Dictionary) -> bool:
	var input_a: Dictionary = slot_state.get(&"input_a", {})
	var input_b: Dictionary = slot_state.get(&"input_b", {})
	var input_a_id: StringName = input_a.get(&"item_id", &"")
	var input_b_id: StringName = input_b.get(&"item_id", &"")
	var input_a_qty := int(input_a.get(&"quantity", 0))
	var input_b_qty := int(input_b.get(&"quantity", 0))
	return (
		(input_a_id == STEEL_SWORD_RECIPE_INPUT and input_a_qty >= 1 and input_b_qty <= 0) or
		(input_b_id == STEEL_SWORD_RECIPE_INPUT and input_b_qty >= 1 and input_a_qty <= 0)
	)


func is_steel_sword_unlocked(is_recipe_unlocked: Callable) -> bool:
	return _is_recipe_unlocked(get_steel_sword_recipe_definition(), is_recipe_unlocked)


func get_steel_sword_recipe_definition() -> Dictionary:
	return {
		&"display_name": "Steel Sword",
		&"discovery_gate": {
			&"entry_id": &"steel",
			&"hint": "Discover Steel in the furnace to unlock advanced forge patterns.",
			&"locked_name": "???",
		},
	}


func get_forge_recipe_definition(output_id: StringName) -> Dictionary:
	if output_id == STEEL_SWORD_RECIPE_OUTPUT:
		return get_steel_sword_recipe_definition()
	return TOOL_RECIPE_DEFINITIONS.get(output_id, {})


func _is_recipe_unlocked(recipe: Dictionary, is_recipe_unlocked: Callable) -> bool:
	if is_recipe_unlocked.is_valid():
		return bool(is_recipe_unlocked.call(recipe))
	return true
