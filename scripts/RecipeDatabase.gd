extends Node

signal recipe_registered(recipe_id: StringName)
signal database_ready(recipe_count: int)

const RECIPE_DATA_PATH := "res://data/recipes/p2_recipes.json"

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

	var file := FileAccess.open(RECIPE_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("Unable to open recipe data file: %s" % RECIPE_DATA_PATH)
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_warning("Skipping invalid recipe data file: %s" % RECIPE_DATA_PATH)
		return

	for raw_recipe in parsed:
		if not raw_recipe is Dictionary:
			push_warning("Skipping malformed recipe entry in %s" % RECIPE_DATA_PATH)
			continue

		var recipe := _normalize_recipe(raw_recipe)
		if recipe.is_empty():
			push_warning("Skipping incomplete recipe entry in %s" % RECIPE_DATA_PATH)
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
		if not raw_input.has(&"element_id") or not raw_input.has(&"qty"):
			return {}

		var qty := int(raw_input.get(&"qty", 0))
		if qty <= 0:
			return {}

		normalized_inputs.append({
			&"element_id": StringName(str(raw_input.get(&"element_id"))),
			&"qty": qty,
		})

	var raw_output = raw_recipe.get(&"output")
	if not raw_output is Dictionary:
		return {}
	if not raw_output.has(&"item_id") or not raw_output.has(&"qty"):
		return {}

	var output_qty := int(raw_output.get(&"qty", 0))
	if output_qty <= 0:
		return {}

	var requires_station = raw_recipe.get(&"requires_station")
	if requires_station != null:
		requires_station = StringName(str(requires_station))

	return {
		&"id": StringName(str(raw_recipe.get(&"id"))),
		&"inputs": normalized_inputs,
		&"output": {
			&"item_id": StringName(str(raw_output.get(&"item_id"))),
			&"qty": output_qty,
		},
		&"durability": clampf(float(raw_recipe.get(&"durability", 1.0)), 0.0, 1.0),
		&"requires_station": requires_station,
	}
