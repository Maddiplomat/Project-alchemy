extends Node

signal crafted(recipe_id: StringName)

var first_craft_completed := false


func can_craft(recipe_id: StringName) -> bool:
	var recipe := RecipeDatabase.get_recipe(recipe_id)
	if recipe.is_empty():
		return false

	for input_data: Dictionary in recipe.get(&"inputs", []):
		var element_id: StringName = input_data.get(&"element_id", &"")
		var required_qty: int = input_data.get(&"qty", 0)
		if element_id.is_empty() or required_qty <= 0:
			return false
		if not InventoryManager.has_item(element_id, required_qty):
			return false

	var output_data := _build_output_item_data(recipe)
	var output_quantity: int = recipe.get(&"output", {}).get(&"qty", 0)
	if output_data.is_empty() or output_quantity <= 0:
		return false

	return InventoryManager.can_add_item(output_data, output_quantity)


func has_any_craftable_recipe() -> bool:
	for recipe_id in RecipeDatabase.get_all_recipes():
		if can_craft(recipe_id):
			return true
	return false


func craft(recipe_id: StringName) -> bool:
	if not can_craft(recipe_id):
		return false

	var recipe := RecipeDatabase.get_recipe(recipe_id)
	for input_data: Dictionary in recipe.get(&"inputs", []):
		var element_id: StringName = input_data.get(&"element_id", &"")
		var required_qty: int = input_data.get(&"qty", 0)
		InventoryManager.remove_element(String(element_id), required_qty)

	var output_data := _build_output_item_data(recipe)
	var output_quantity: int = recipe.get(&"output", {}).get(&"qty", 0)
	if not InventoryManager.add_item(output_data, output_quantity):
		return false

	first_craft_completed = true

	crafted.emit(recipe_id)
	return true


func _build_output_item_data(recipe: Dictionary) -> Dictionary:
	var output: Dictionary = recipe.get(&"output", {})
	var item_id: StringName = output.get(&"item_id", &"")
	if item_id.is_empty():
		return {}

	var durability := clampf(float(recipe.get(&"durability", 1.0)), 0.0, 1.0)
	return {
		&"id": item_id,
		&"display_name": _format_item_name(item_id),
		&"category": InventoryManager.InventoryItemCategory.CRAFTED,
		&"durability": durability,
		&"max_durability": durability,
	}


func _format_item_name(item_id: StringName) -> String:
	var words := String(item_id).split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)
