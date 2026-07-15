class_name RecipeDatabaseResource
extends Resource

signal recipe_unlocked(recipe_id: StringName)
signal database_ready(recipe_count: int)

const RECIPE_DATA_DIR := "res://data/recipes"
const INVENTORY_STATION_ID := &"inventory"

# Recipe dict: id -> {id, name, station, inputs: [{id, qty}], output: {id, qty},
#                     unlocked: bool, requires_discovery: StringName}
var recipes: Dictionary[StringName, Dictionary] = {}
var _initialized := false



func init() -> RecipeDatabaseResource:
	if _initialized:
		return self
	_initialized = true
	_load_recipes()
	database_ready.emit(recipes.size())
	return self


func has_recipe(recipe_id: StringName) -> bool:
	init()
	return recipes.has(recipe_id)


func get_recipe(id: StringName) -> Dictionary:
	init()
	if not recipes.has(id):
		return {}
	var recipe := (recipes[id] as Dictionary).duplicate(true)
	recipe[&"unlocked"] = _is_recipe_unlocked(recipe)
	return recipe


func get_all_recipes() -> Dictionary[StringName, Dictionary]:
	init()
	var result: Dictionary[StringName, Dictionary] = {}
	for recipe_id: StringName in recipes.keys():
		result[recipe_id] = get_recipe(recipe_id)
	return result


func get_all_unlocked() -> Array[Dictionary]:
	init()
	var unlocked_recipes: Array[Dictionary] = []
	for recipe_id: StringName in recipes.keys():
		var recipe := get_recipe(recipe_id)
		if bool(recipe.get(&"unlocked", false)):
			unlocked_recipes.append(recipe)
	return unlocked_recipes


func reset_runtime_state() -> void:
	init()
	_load_recipes()


func unlock_recipe(recipe_id: StringName) -> bool:
	init()
	if not recipes.has(recipe_id):
		return false

	var recipe: Dictionary = recipes[recipe_id]
	if bool(recipe.get(&"unlocked", false)):
		return false

	recipe[&"unlocked"] = true
	recipes[recipe_id] = recipe
	recipe_unlocked.emit(recipe_id)
	return true


func get_recipes_for_station(station_id: StringName) -> Array[Dictionary]:
	init()
	var station_recipes: Array[Dictionary] = []
	for recipe_id: StringName in recipes.keys():
		var recipe := get_recipe(recipe_id)
		if StringName(recipe.get(&"station", &"")) == station_id:
			station_recipes.append(recipe)
	return station_recipes


func get_recipes_for_output(item_id: StringName) -> Array[Dictionary]:
	init()
	var result: Array[Dictionary] = []
	for recipe_id: StringName in recipes.keys():
		var recipe := get_recipe(recipe_id)
		var output: Dictionary = recipe.get(&"output", {})
		if StringName(output.get(&"item_id", output.get(&"id", &""))) == item_id:
			result.append(recipe)
	return result


func is_inventory_station(station_id: StringName) -> bool:
	return station_id == INVENTORY_STATION_ID


func _load_recipes() -> void:
	recipes.clear()

	var recipe_data := _load_recipe_data_files()
	for recipe: Dictionary in recipe_data:
		_register_recipe(recipe)


func _load_recipe_data_files() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file_names := DirAccess.get_files_at(RECIPE_DATA_DIR)

	for file_name in file_names:
		if not file_name.ends_with(".json"):
			continue

		var file_path := RECIPE_DATA_DIR.path_join(file_name)
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			push_warning("Unable to open recipe data file: %s" % file_path)
			continue

		var parsed = JSON.parse_string(file.get_as_text())
		if not parsed is Array:
			push_warning("Skipping invalid recipe data file: %s" % file_path)
			continue

		for raw_recipe in parsed:
			if not raw_recipe is Dictionary:
				push_warning("Skipping malformed recipe entry in: %s" % file_path)
				continue

			var normalized := _normalize_recipe_data(raw_recipe)
			if normalized.is_empty():
				push_warning("Skipping incomplete recipe entry in: %s" % file_path)
				continue
			result.append(normalized)

	return result


func _normalize_recipe_data(raw_recipe: Dictionary) -> Dictionary:
	var recipe_id := StringName(str(raw_recipe.get(&"id", "")))
	if recipe_id.is_empty():
		return {}

	var normalized_inputs := _normalize_inputs(raw_recipe.get(&"inputs", []))
	if normalized_inputs.is_empty():
		return {}

	var normalized_output := _normalize_output(raw_recipe.get(&"output", {}))
	if normalized_output.is_empty():
		return {}

	var requires_discovery := _resolve_requires_discovery(raw_recipe)
	var discovery_gate := _normalize_discovery_gate(raw_recipe.get(&"discovery_gate", {}), requires_discovery)

	return {
		&"id": recipe_id,
		&"name": str(raw_recipe.get(&"name", _format_name(recipe_id))),
		&"station": _normalize_station_id(recipe_id, StringName(str(raw_recipe.get(&"station", "")))),
		&"inputs": normalized_inputs,
		&"output": normalized_output,
		&"unlocked": bool(raw_recipe.get(&"unlocked", requires_discovery.is_empty())),
		&"requires_discovery": requires_discovery,
		&"discovery_gate": discovery_gate,
		&"durability": raw_recipe.get(&"durability", null),
		&"ratio": raw_recipe.get(&"ratio", {}).duplicate(true) if raw_recipe.get(&"ratio", {}) is Dictionary else {},
		&"required_temp": raw_recipe.get(&"required_temp", null),
		&"reaction_type": str(raw_recipe.get(&"reaction_type", "")),
		&"process_hint": str(raw_recipe.get(&"process_hint", "")),
		&"ratio_hint": str(raw_recipe.get(&"ratio_hint", "")),
		&"temperature_hint": str(raw_recipe.get(&"temperature_hint", "")),
	}


func _normalize_inputs(raw_inputs) -> Array[Dictionary]:
	if not raw_inputs is Array:
		return []

	var normalized_inputs: Array[Dictionary] = []
	for raw_input in raw_inputs:
		if not raw_input is Dictionary:
			continue

		var input_id := StringName(str(raw_input.get(&"element_id", raw_input.get(&"id", ""))))
		var input_qty := int(raw_input.get(&"qty", 0))
		if input_id.is_empty() or input_qty <= 0:
			for raw_key in raw_input.keys():
				if String(raw_key) == "qty":
					continue
				input_id = StringName(str(raw_key))
				input_qty = int(raw_input[raw_key])
				break

		if input_id.is_empty() or input_qty <= 0:
			continue

		normalized_inputs.append({
			&"id": input_id,
			&"element_id": input_id,
			&"qty": input_qty,
		})

	return normalized_inputs


func _normalize_output(raw_output) -> Dictionary:
	if not raw_output is Dictionary:
		return {}

	var output_id := StringName(str(raw_output.get(&"item_id", raw_output.get(&"id", ""))))
	var output_qty := int(raw_output.get(&"qty", 0))
	if output_id.is_empty() or output_qty <= 0:
		for raw_key in raw_output.keys():
			if String(raw_key) == "qty":
				continue
			output_id = StringName(str(raw_key))
			output_qty = int(raw_output[raw_key])
			break

	if output_id.is_empty() or output_qty <= 0:
		return {}

	return {
		&"id": output_id,
		&"item_id": output_id,
		&"qty": output_qty,
	}


func _resolve_requires_discovery(raw_recipe: Dictionary) -> StringName:
	if raw_recipe.has(&"requires_discovery"):
		return StringName(str(raw_recipe.get(&"requires_discovery", "")))

	var raw_gate = raw_recipe.get(&"discovery_gate", {})
	if raw_gate is Dictionary:
		return StringName(str(raw_gate.get(&"entry_id", "")))
	return &""


func _normalize_discovery_gate(raw_gate, requires_discovery: StringName) -> Dictionary:
	if requires_discovery.is_empty():
		return {}

	var normalized_gate := {
		&"entry_id": requires_discovery,
		&"hint": _build_discovery_hint(requires_discovery),
		&"locked_name": "???",
	}
	if raw_gate is Dictionary:
		if raw_gate.has(&"hint"):
			normalized_gate[&"hint"] = str(raw_gate.get(&"hint", normalized_gate[&"hint"]))
		if raw_gate.has(&"locked_name"):
			normalized_gate[&"locked_name"] = str(raw_gate.get(&"locked_name", normalized_gate[&"locked_name"]))
	return normalized_gate


func _normalize_station_id(recipe_id: StringName, station_id: StringName) -> StringName:
	if station_id.is_empty() and recipe_id == &"distillation_kit":
		return INVENTORY_STATION_ID
	return station_id


func _register_recipe(recipe: Dictionary) -> void:
	var recipe_id := StringName(recipe.get(&"id", &""))
	if recipe_id.is_empty():
		return
	recipes[recipe_id] = recipe


func _is_recipe_unlocked(recipe: Dictionary) -> bool:
	if bool(recipe.get(&"unlocked", false)):
		return true

	var required_discovery := StringName(recipe.get(&"requires_discovery", &""))
	if required_discovery.is_empty():
		return false

	var discovery_log := EventBus.get_discovery_log()
	if discovery_log != null and discovery_log.has_method("has_discovery"):
		return bool(discovery_log.has_discovery(required_discovery))

	return false


func _build_discovery_hint(discovery_id: StringName) -> String:
	match discovery_id:
		&"distillation_kit":
			return "Discover the Distillation Kit before attempting sulfur chemistry."
		&"stabilization_success":
			return "Achieve a successful stabilization to identify buffered sulfur chemistry."
		&"mercury_handling":
			return "Recover mercury from Sodium Shoals before attempting mercury chemistry."
		_:
			return "Discover %s to unlock this recipe." % _format_name(discovery_id)


func _format_name(value: StringName) -> String:
	var words := String(value).split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)
