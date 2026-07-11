extends SceneTree

const FurnacePredictionScript = preload("res://scripts/FurnacePrediction.gd")

var _failures := 0


func _init() -> void:
	_run_test()
	quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var prediction = FurnacePredictionScript.new()
	var tool_element_resolver := func(item_id: StringName) -> Dictionary:
		match item_id:
			&"wood":
				return {
					&"display_name": "Wood",
					&"symbol": "C",
					&"properties": {
						&"carbon_pct_when_burned": 1.0,
						&"steel_window_carbon_min_pct": 0.5,
						&"steel_window_carbon_max_pct": 2.1,
					},
				}
			&"iron":
				return {&"display_name": "Iron", &"properties": {}}
			_:
				return {}
	var alloy_element_resolver := func(item_id: StringName) -> Dictionary:
		match item_id:
			&"charcoal":
				return {
					&"display_name": "Charcoal",
					&"symbol": "C",
					&"properties": {
						&"carbon_pct_when_burned": 1.0,
						&"steel_window_carbon_min_pct": 0.5,
						&"steel_window_carbon_max_pct": 2.1,
					},
				}
			&"iron":
				return {&"display_name": "Iron", &"properties": {}}
			_:
				return {}
	var label_resolver := func(item_id: StringName) -> String:
		return String(item_id).replace("_", " ").capitalize()
	var lock_hint_resolver := func(_item_id: StringName) -> String:
		return "locked"
	var tool_unlock_resolver := func(recipe: Dictionary) -> bool:
		return bool(recipe.get(&"display_name", "") != "Steel Sword")
	var open_unlock_resolver := func(_recipe: Dictionary) -> bool:
		return true
	var reaction_evaluator := func(element_a: String, element_b: String, ratio_b_pct: float, temp: float) -> Dictionary:
		if temp < 1200.0:
			return {"output_id": null, "tier": "unknown", "quality": 0.0, "notes": "Heat too low"}
		if element_a == "iron" and element_b == "charcoal" and ratio_b_pct >= 0.5 and ratio_b_pct <= 2.1:
			return {"output_id": "steel", "tier": "optimal", "quality": 1.0, "notes": "Optimal"}
		return {"output_id": null, "tier": "unknown", "quality": 0.0, "notes": "No reaction"}

	var slot_state: Dictionary = {
		&"input_a": {&"item_id": &"iron", &"quantity": 2},
		&"input_b": {&"item_id": &"wood", &"quantity": 2},
	}
	var preview := prediction.build_output_preview(
		slot_state,
		1300.0,
		false,
		1.0,
		[],
		0,
		&"charcoal",
		tool_element_resolver,
		label_resolver,
		lock_hint_resolver,
		tool_unlock_resolver,
		reaction_evaluator
	)

	_assert(preview.get(&"kind", "") == "output", "Expected forge recipe preview to resolve to an output slot state.")
	_assert(preview.get(&"output_id", &"") == &"iron_axe", "Expected iron+wood to preview Iron Axe.")

	var alloy_slot_state: Dictionary = {
		&"input_a": {&"item_id": &"iron", &"quantity": 1},
		&"input_b": {&"item_id": &"charcoal", &"quantity": 1},
	}
	var alloy_prediction := prediction.build_output_preview(
		alloy_slot_state,
		1300.0,
		false,
		1.0,
		[],
		0,
		&"charcoal",
		alloy_element_resolver,
		label_resolver,
		lock_hint_resolver,
		open_unlock_resolver,
		reaction_evaluator
	)

	_assert(alloy_prediction.get(&"kind", "") == "prediction", "Expected alloy pair to produce a prediction result.")
	var result: Dictionary = alloy_prediction.get(&"prediction", {})
	_assert(StringName(str(result.get(&"output_id", ""))) == &"steel", "Expected 1%% carbon preview to predict Steel.")

	if _failures == 0:
		print("FurnacePredictionTest passed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
