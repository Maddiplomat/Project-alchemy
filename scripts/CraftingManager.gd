extends Node
# Autoload: CraftingManager

signal crafting_started(recipe_id: StringName)
signal crafting_completed(recipe_id: StringName, output: Dictionary)
signal crafting_failed(recipe_id: StringName, reason: String)
signal crafted(recipe_id: StringName)

var first_craft_completed := false


func can_craft(recipe_id: StringName) -> bool:
	var recipe := RecipeDatabase.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if not _is_recipe_unlocked(recipe):
		return false

	var output_data := _build_output_item_data(recipe)
	var output_quantity := _get_output_quantity(recipe)
	if output_data.is_empty() or output_quantity <= 0:
		return false

	for input_data: Dictionary in recipe.get(&"inputs", []):
		var element_id := _get_input_id(input_data)
		var required_qty := int(input_data.get(&"qty", 0))
		if element_id.is_empty() or required_qty <= 0:
			return false
		if not InventoryManager.has_item(element_id, required_qty):
			return false

	return InventoryManager.can_add_item(output_data, output_quantity)


func get_craftable_recipe() -> Dictionary:
	var recipe_ids: Array[String] = []
	for recipe_id: StringName in RecipeDatabase.get_all_recipes().keys():
		recipe_ids.append(String(recipe_id))
	recipe_ids.sort()

	for recipe_id_text: String in recipe_ids:
		var recipe_id := StringName(recipe_id_text)
		var recipe := RecipeDatabase.get_recipe(recipe_id)
		if recipe.is_empty():
			continue
		if StringName(recipe.get(&"station", &"")) != &"":
			continue
		if can_craft(recipe_id):
			return recipe

	return {}


func has_any_craftable_recipe() -> bool:
	return not get_craftable_recipe().is_empty()


func craft(recipe_id: StringName, station_id: StringName = &"") -> bool:
	var recipe := RecipeDatabase.get_recipe(recipe_id)
	if recipe.is_empty():
		crafting_failed.emit(recipe_id, "recipe_missing")
		return false
	if not _is_recipe_unlocked(recipe):
		crafting_failed.emit(recipe_id, "recipe_locked")
		return false
	if not can_craft(recipe_id):
		crafting_failed.emit(recipe_id, "requirements_missing")
		return false
	if not _is_station_valid(recipe, station_id):
		crafting_failed.emit(recipe_id, "invalid_station")
		return false

	var output_data := _build_output_item_data(recipe)
	var output_quantity := _get_output_quantity(recipe)
	if output_data.is_empty() or output_quantity <= 0:
		crafting_failed.emit(recipe_id, "invalid_output")
		return false

	crafting_started.emit(recipe_id)

	var removed_inputs: Array[Dictionary] = []
	for input_data: Dictionary in recipe.get(&"inputs", []):
		var element_id := _get_input_id(input_data)
		var required_qty := int(input_data.get(&"qty", 0))
		InventoryManager.remove_element(element_id, required_qty)
		removed_inputs.append({
			&"item_id": element_id,
			&"qty": required_qty,
		})

	if not InventoryManager.add_item(output_data, output_quantity):
		for removed_input: Dictionary in removed_inputs:
			InventoryManager.add_element(
				StringName(removed_input.get(&"item_id", &"")),
				int(removed_input.get(&"qty", 0)),
				1.0
			)
		crafting_failed.emit(recipe_id, "inventory_add_failed")
		return false

	first_craft_completed = true
	crafted.emit(recipe_id)
	crafting_completed.emit(recipe_id, output_data.duplicate(true))
	return true


func _build_output_item_data(recipe: Dictionary) -> Dictionary:
	var output: Dictionary = recipe.get(&"output", {})
	var item_id: StringName = StringName(output.get(&"item_id", output.get(&"id", &"")))
	if item_id.is_empty():
		return {}

	var item_data := {
		&"id": item_id,
		&"display_name": _format_item_name(item_id),
		&"category": InventoryManager.InventoryItemCategory.TOOL if item_id == &"distillation_kit" else InventoryManager.InventoryItemCategory.CRAFTED,
	}

	if item_id == &"distillation_kit":
		item_data[&"tool_type"] = "distillation_kit"
	elif item_id == &"rust_bolt":
		item_data[&"category"] = InventoryManager.InventoryItemCategory.CONSUMABLE
		item_data[&"weapon_type"] = "ranged"
		item_data[&"projectile_id"] = "rust_bolt"
		item_data[&"damage_type"] = "oxidation"
		item_data[&"base_damage"] = 15.0
	elif item_id == &"sulfuric_bolt":
		item_data[&"category"] = InventoryManager.InventoryItemCategory.CONSUMABLE
		item_data[&"weapon_type"] = "ranged"
		item_data[&"projectile_id"] = "sulfuric_bolt"
		item_data[&"damage_type"] = "chemical"
		item_data[&"base_damage"] = 22.0
	elif item_id == &"corrosive_slurry":
		item_data[&"category"] = InventoryManager.InventoryItemCategory.CONSUMABLE
		item_data[&"mixture_type"] = "corrosive_slurry"

	var durability = recipe.get(&"durability")
	if durability != null:
		var normalized_durability := clampf(float(durability), 0.0, 1.0)
		item_data[&"durability"] = normalized_durability
		item_data[&"max_durability"] = normalized_durability

	return item_data


func _get_output_quantity(recipe: Dictionary) -> int:
	var output: Dictionary = recipe.get(&"output", {})
	return int(output.get(&"qty", 0))


func _get_input_id(input_data: Dictionary) -> StringName:
	return StringName(input_data.get(&"element_id", input_data.get(&"id", &"")))


func _format_item_name(item_id: StringName) -> String:
	var words := String(item_id).split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)


func _is_recipe_unlocked(recipe: Dictionary) -> bool:
	if DiscoveryLog != null and DiscoveryLog.has_method("is_recipe_unlocked"):
		return bool(DiscoveryLog.is_recipe_unlocked(recipe))
	return bool(recipe.get(&"unlocked", true))


func _is_station_valid(recipe: Dictionary, station_id: StringName) -> bool:
	var required_station := StringName(recipe.get(&"station", &""))
	if required_station.is_empty():
		return station_id.is_empty()
	return station_id == required_station
