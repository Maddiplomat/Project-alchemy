extends Node

signal recipe_registered(recipe_id: StringName)
signal database_ready(recipe_count: int)

const RECIPE_DATA_DIR := "res://data/recipes"

var recipes: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	_load_recipes()
	database_ready.emit(recipes.size())


func has_recipe(recipe_id: StringName) -> bool:
	return recipes.has(recipe_id)


func get_recipe(recipe_id: StringName) -> Dictionary:
	if not has_recipe(recipe_id):
		return {}

	return recipes[recipe_id].duplicate(true)


func get_all_recipes() -> Dictionary[StringName, Dictionary]:
	var result: Dictionary[StringName, Dictionary] = {}
	for recipe_id: StringName in recipes:
		result[recipe_id] = recipes[recipe_id].duplicate(true)

	return result


func get_recipes_for_output(item_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id: StringName in recipes:
		var recipe: Dictionary = recipes[recipe_id]
		var output: Dictionary = recipe.get(&"output", {})
		if output.get(&"item_id", &"") == item_id:
			result.append(recipe.duplicate(true))

	return result


func _load_recipes() -> void:
	recipes.clear()
	var dir := DirAccess.open(RECIPE_DATA_DIR)
	if dir == null:
		push_warning("Unable to open recipe data directory: %s" % RECIPE_DATA_DIR)
		return
	var file_names := dir.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if not file_name.ends_with(".json"):
			continue
		_load_recipe_file("%s/%s" % [RECIPE_DATA_DIR, file_name])


func _load_recipe_file(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("Unable to open recipe data file: %s" % file_path)
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_warning("Skipping invalid recipe data file: %s" % file_path)
		return

	for raw_recipe in parsed:
		if not raw_recipe is Dictionary:
			push_warning("Skipping malformed recipe entry in %s" % file_path)
			continue

		var recipe := _normalize_recipe(raw_recipe)
		if recipe.is_empty():
			push_warning("Skipping incomplete recipe entry in %s" % file_path)
			continue

		var recipe_id: StringName = recipe.get(&"id", &"")
		recipes[recipe_id] = recipe
		recipe_registered.emit(recipe_id)


func _normalize_recipe(raw_recipe: Dictionary) -> Dictionary:
	var required_keys := [&"id", &"inputs", &"output"]
	for key: StringName in required_keys:
		if not raw_recipe.has(key):
			return {}

	var raw_inputs = raw_recipe.get(&"inputs")
	if not raw_inputs is Array:
		return {}

	var normalized_inputs: Array[Dictionary] = []
	for raw_input in raw_inputs:
		if not raw_input is Dictionary:
			return {}
		var normalized_input := _normalize_recipe_input(raw_input)
		if normalized_input.is_empty():
			return {}
		var qty := int(normalized_input.get(&"qty", 0))
		if qty <= 0:
			return {}
		normalized_inputs.append(normalized_input)

	var raw_output = raw_recipe.get(&"output")
	if not raw_output is Dictionary:
		return {}
	var normalized_output := _normalize_recipe_output(raw_output)
	if normalized_output.is_empty():
		return {}

	var output_qty := int(normalized_output.get(&"qty", 0))
	if output_qty <= 0:
		return {}

	var station_value = raw_recipe.get(&"station", raw_recipe.get(&"requires_station"))
	var station: Variant = null
	if station_value != null:
		station = StringName(str(station_value))

	var ratio: Dictionary[StringName, float] = {}
	var raw_ratio = raw_recipe.get(&"ratio", {})
	if raw_ratio is Dictionary:
		for ratio_key in raw_ratio.keys():
			ratio[StringName(str(ratio_key))] = float(raw_ratio[ratio_key])

	var durability: Variant = null
	if raw_recipe.has(&"durability"):
		var raw_durability = raw_recipe.get(&"durability")
		if raw_durability != null:
			durability = clampf(float(raw_durability), 0.0, 1.0)
	else:
		durability = 1.0

	return {
		&"id": StringName(str(raw_recipe.get(&"id"))),
		&"inputs": normalized_inputs,
		&"output": {
			&"item_id": StringName(str(normalized_output.get(&"item_id"))),
			&"qty": output_qty,
		},
		&"durability": durability,
		&"station": station,
		&"requires_station": station,
		&"ratio": ratio,
		&"required_temp": raw_recipe.get(&"required_temp"),
		&"reaction_type": StringName(str(raw_recipe.get(&"reaction_type", ""))),
		&"requires_stabilization": bool(raw_recipe.get(&"requires_stabilization", false)),
	}


func _normalize_recipe_input(raw_input: Dictionary) -> Dictionary:
	if raw_input.has(&"element_id") and raw_input.has(&"qty"):
		return {
			&"element_id": StringName(str(raw_input.get(&"element_id"))),
			&"qty": int(raw_input.get(&"qty", 0)),
		}

	if raw_input.size() != 1:
		return {}

	var element_key = raw_input.keys()[0]
	return {
		&"element_id": StringName(str(element_key)),
		&"qty": int(raw_input[element_key]),
	}


func _normalize_recipe_output(raw_output: Dictionary) -> Dictionary:
	if raw_output.has(&"item_id") and raw_output.has(&"qty"):
		return {
			&"item_id": StringName(str(raw_output.get(&"item_id"))),
			&"qty": int(raw_output.get(&"qty", 0)),
		}

	if raw_output.size() != 1:
		return {}

	var item_key = raw_output.keys()[0]
	return {
		&"item_id": StringName(str(item_key)),
		&"qty": int(raw_output[item_key]),
	}
