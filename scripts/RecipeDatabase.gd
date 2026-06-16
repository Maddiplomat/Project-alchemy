extends Node
# Autoload: RecipeDatabase

signal recipe_unlocked(recipe_id: StringName)
signal database_ready(recipe_count: int)

# Recipe dict: id -> {id, name, station, inputs: [{id, qty}], output: {id, qty},
#                     unlocked: bool, requires_discovery: StringName}
var recipes: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	_seed_recipes()
	database_ready.emit(recipes.size())


func has_recipe(recipe_id: StringName) -> bool:
	return recipes.has(recipe_id)


func get_recipe(id: StringName) -> Dictionary:
	if not recipes.has(id):
		return {}
	var recipe := (recipes[id] as Dictionary).duplicate(true)
	recipe[&"unlocked"] = _is_recipe_unlocked(recipe)
	return recipe


func get_all_recipes() -> Dictionary[StringName, Dictionary]:
	var result: Dictionary[StringName, Dictionary] = {}
	for recipe_id: StringName in recipes.keys():
		result[recipe_id] = get_recipe(recipe_id)
	return result


func get_all_unlocked() -> Array[Dictionary]:
	var unlocked_recipes: Array[Dictionary] = []
	for recipe_id: StringName in recipes.keys():
		var recipe := get_recipe(recipe_id)
		if bool(recipe.get(&"unlocked", false)):
			unlocked_recipes.append(recipe)
	return unlocked_recipes


func unlock_recipe(recipe_id: StringName) -> bool:
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
	var station_recipes: Array[Dictionary] = []
	for recipe_id: StringName in recipes.keys():
		var recipe := get_recipe(recipe_id)
		if StringName(recipe.get(&"station", &"")) == station_id:
			station_recipes.append(recipe)
	return station_recipes


func get_recipes_for_output(item_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id: StringName in recipes.keys():
		var recipe := get_recipe(recipe_id)
		var output: Dictionary = recipe.get(&"output", {})
		if StringName(output.get(&"item_id", output.get(&"id", &""))) == item_id:
			result.append(recipe)
	return result


func _seed_recipes() -> void:
	recipes.clear()

	_register_recipe(_make_recipe(
		&"charcoal",
		"Charcoal",
		&"furnace",
		[{&"id": &"wood", &"qty": 1}],
		{&"id": &"charcoal", &"qty": 1}
	))
	_register_recipe(_make_recipe(
		&"wrought_iron",
		"Wrought Iron",
		&"furnace",
		[{&"id": &"iron", &"qty": 1}, {&"id": &"charcoal", &"qty": 1}],
		{&"id": &"wrought_iron", &"qty": 1}
	))
	_register_recipe(_make_recipe(
		&"steel",
		"Steel",
		&"furnace",
		[{&"id": &"iron", &"qty": 1}, {&"id": &"charcoal", &"qty": 1}],
		{&"id": &"steel", &"qty": 1}
	))
	_register_recipe(_make_recipe(
		&"cast_iron",
		"Cast Iron",
		&"furnace",
		[{&"id": &"iron", &"qty": 1}, {&"id": &"charcoal", &"qty": 1}],
		{&"id": &"cast_iron", &"qty": 1}
	))
	_register_recipe(_make_recipe(
		&"rust_bolt",
		"Rust Bolt",
		&"chem_bench",
		[{&"id": &"iron", &"qty": 2}, {&"id": &"water", &"qty": 1}],
		{&"id": &"rust_bolt", &"qty": 8}
	))
	_register_recipe(_make_recipe(
		&"sulfuric_bolt",
		"Sulfuric Bolt",
		&"chem_bench",
		[{&"id": &"sulfur", &"qty": 1}, {&"id": &"iron", &"qty": 1}],
		{&"id": &"sulfuric_bolt", &"qty": 6},
		false,
		&"distillation_kit"
	))
	_register_recipe(_make_recipe(
		&"corrosive_slurry",
		"Corrosive Slurry",
		&"chem_bench",
		[{&"id": &"sulfur", &"qty": 1}, {&"id": &"water", &"qty": 1}],
		{&"id": &"corrosive_slurry", &"qty": 1},
		false,
		&"stabilization_success"
	))
	_register_recipe(_make_recipe(
		&"distillation_kit",
		"Distillation Kit",
		&"",
		[{&"id": &"iron", &"qty": 2}, {&"id": &"wood", &"qty": 3}],
		{&"id": &"distillation_kit", &"qty": 1},
		true,
		&"",
		1.0
	))


func _register_recipe(recipe: Dictionary) -> void:
	var recipe_id := StringName(recipe.get(&"id", &""))
	if recipe_id.is_empty():
		return
	recipes[recipe_id] = recipe


func _make_recipe(
	recipe_id: StringName,
	recipe_name: String,
	station_id: StringName,
	inputs: Array,
	output: Dictionary,
	unlocked: bool = true,
	requires_discovery: StringName = &"",
	durability = null
) -> Dictionary:
	var normalized_inputs: Array[Dictionary] = []
	for input_entry: Dictionary in inputs:
		normalized_inputs.append({
			&"id": StringName(input_entry.get(&"id", &"")),
			&"element_id": StringName(input_entry.get(&"id", &"")),
			&"qty": int(input_entry.get(&"qty", 0)),
		})

	var output_id := StringName(output.get(&"id", &""))
	var output_qty := int(output.get(&"qty", 0))
	var discovery_gate := {}
	if not requires_discovery.is_empty():
		discovery_gate = {
			&"entry_id": requires_discovery,
			&"hint": _build_discovery_hint(requires_discovery),
			&"locked_name": "???",
		}

	return {
		&"id": recipe_id,
		&"name": recipe_name,
		&"station": station_id,
		&"inputs": normalized_inputs,
		&"output": {
			&"id": output_id,
			&"item_id": output_id,
			&"qty": output_qty,
		},
		&"unlocked": unlocked,
		&"requires_discovery": requires_discovery,
		&"discovery_gate": discovery_gate,
		&"durability": durability,
	}


func _is_recipe_unlocked(recipe: Dictionary) -> bool:
	if bool(recipe.get(&"unlocked", false)):
		return true

	var required_discovery := StringName(recipe.get(&"requires_discovery", &""))
	if required_discovery.is_empty():
		return false

	if DiscoveryLog != null and DiscoveryLog.has_method("has_discovery"):
		return bool(DiscoveryLog.has_discovery(required_discovery))

	return false


func _build_discovery_hint(discovery_id: StringName) -> String:
	match discovery_id:
		&"distillation_kit":
			return "Discover the Distillation Kit before attempting sulfur chemistry."
		&"stabilization_success":
			return "Achieve a successful stabilization to identify buffered sulfur chemistry."
		_:
			return "Discover %s to unlock this recipe." % _format_name(discovery_id)


func _format_name(value: StringName) -> String:
	var words := String(value).split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)
