extends Node

signal chest_inventory_changed(chest_id: StringName)

const DEFAULT_SLOT_COUNT := 20
const EMPTY_ITEM := &""
const FILTER_ANY := &"any"
const FILTER_VOLATILE_ELEMENTS := &"volatile_elements"
const FILTER_WATER_REACTIVE_ELEMENTS := &"water_reactive_elements"

var chest_inventories: Dictionary = {}
var container_configs: Dictionary = {}


func ensure_container(chest_id: StringName, config: Dictionary = {}) -> void:
	if chest_id.is_empty():
		return
	_register_container_config(chest_id, config)
	if chest_inventories.has(chest_id):
		_ensure_slot_count(chest_id)
		return
	chest_inventories[chest_id] = {
		&"items": {},
		&"slot_order": _build_empty_slot_order(get_slot_count(chest_id)),
	}


func ensure_chest(chest_id: StringName) -> void:
	ensure_container(chest_id, {
		&"slot_count": DEFAULT_SLOT_COUNT,
		&"title": "Storage Chest",
		&"filter_id": FILTER_ANY,
	})


func generate_chest_id() -> StringName:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var parts: Array[String] = []
	for count in [8, 4, 4, 4, 12]:
		var part := ""
		for _i in range(count):
			part += "%x" % rng.randi_range(0, 15)
		parts.append(part)
	return StringName("-".join(parts))


func get_slot_item(chest_id: StringName, slot_index: int) -> Dictionary:
	ensure_container(chest_id)
	var slot_order: Array[StringName] = chest_inventories[chest_id][&"slot_order"]
	if slot_index < 0 or slot_index >= slot_order.size():
		return {}
	var item_id: StringName = slot_order[slot_index]
	if item_id.is_empty():
		return {}
	var items: Dictionary = chest_inventories[chest_id][&"items"]
	if not items.has(item_id):
		return {}
	var stack: Dictionary = (items[item_id] as Dictionary).duplicate(true)
	stack[&"id"] = String(item_id)
	return stack


func swap_slots(chest_id: StringName, from_slot: int, to_slot: int) -> void:
	ensure_container(chest_id)
	var slot_order: Array[StringName] = chest_inventories[chest_id][&"slot_order"]
	if from_slot < 0 or from_slot >= slot_order.size():
		return
	if to_slot < 0 or to_slot >= slot_order.size():
		return
	if from_slot == to_slot:
		return
	var temp: StringName = slot_order[from_slot]
	slot_order[from_slot] = slot_order[to_slot]
	slot_order[to_slot] = temp
	chest_inventories[chest_id][&"slot_order"] = slot_order
	_emit_changed(chest_id)


func store_from_player(chest_id: StringName, player_slot_index: int, chest_slot_index: int, quantity: int) -> bool:
	ensure_container(chest_id)
	var player_item := InventoryManager.get_slot_data(player_slot_index)
	if player_item.item_id == &"":
		return false
	if not can_store_item(chest_id, player_item):
		return false
	var item_id := StringName(String(player_item.item_id))
	var available_quantity := int(player_item.get(&"quantity", 0))
	quantity = mini(quantity, available_quantity)
	if item_id.is_empty() or quantity <= 0:
		return false

	var target_item := get_slot_item(chest_id, chest_slot_index)
	if not target_item.is_empty() and StringName(str(target_item.get(&"id", ""))) != item_id:
		return false

	if InventoryManager.get_stack(item_id).quantity < quantity:
		return false
	InventoryManager.remove_element(item_id, quantity)

	_store_item_into_slot(chest_id, player_item, quantity, chest_slot_index)
	_emit_changed(chest_id)
	return true


func withdraw_to_player(chest_id: StringName, chest_slot_index: int, player_slot_index: int, quantity: int) -> bool:
	ensure_container(chest_id)
	var chest_item := get_slot_item(chest_id, chest_slot_index)
	if chest_item.is_empty():
		return false
	var item_id := StringName(str(chest_item.get(&"id", "")))
	var available_quantity := int(chest_item.get(&"quantity", 0))
	quantity = mini(quantity, available_quantity)
	if item_id.is_empty() or quantity <= 0:
		return false

	var target_item := InventoryManager.get_slot_data(player_slot_index)
	if target_item.item_id != &"" and StringName(String(target_item.item_id)) != item_id:
		return false

	if not _remove_item(chest_id, item_id, quantity):
		return false

	if not InventoryManager.add_item(chest_item, quantity):
		_store_item_into_slot(chest_id, chest_item, quantity, chest_slot_index)
		_emit_changed(chest_id)
		return false

	_emit_changed(chest_id)
	return true


func export_to_world_save_data(world_save_data) -> void:
	if world_save_data == null:
		return
	world_save_data.chest_inventories = serialize_inventories()


func import_from_world_save_data(world_save_data) -> void:
	if world_save_data == null:
		return
	import_serialized_inventories(world_save_data.chest_inventories)


func serialize_inventories() -> Dictionary:
	var serialized := {}
	for chest_id: StringName in chest_inventories.keys():
		var items: Dictionary = chest_inventories[chest_id][&"items"]
		var slot_order: Array[StringName] = chest_inventories[chest_id][&"slot_order"]
		var serialized_items := {}
		for item_id: StringName in items.keys():
			serialized_items[String(item_id)] = (items[item_id] as Dictionary).duplicate(true)
		var serialized_slots: Array[String] = []
		for slot_item_id: StringName in slot_order:
			serialized_slots.append(String(slot_item_id))
		serialized[String(chest_id)] = {
			&"items": serialized_items,
			&"slot_order": serialized_slots,
		}
	return serialized


func import_serialized_inventories(serialized_inventories: Dictionary) -> void:
	chest_inventories.clear()
	for raw_chest_id in serialized_inventories.keys():
		var chest_id := StringName(str(raw_chest_id))
		var serialized_entry: Variant = serialized_inventories[raw_chest_id]
		if not (serialized_entry is Dictionary):
			continue
		ensure_container(chest_id)
		var entry := serialized_entry as Dictionary
		var serialized_items: Dictionary = entry.get(&"items", {})
		var items: Dictionary = {}
		for raw_item_id in serialized_items.keys():
			var item_id := StringName(str(raw_item_id))
			var item_data: Variant = serialized_items[raw_item_id]
			if item_data is Dictionary:
				items[item_id] = (item_data as Dictionary).duplicate(true)
		var slot_order: Array[StringName] = []
		for raw_slot_item_id in entry.get(&"slot_order", []):
			slot_order.append(StringName(str(raw_slot_item_id)))
		chest_inventories[chest_id] = {
			&"items": items,
			&"slot_order": slot_order,
		}
		_ensure_slot_count(chest_id)


func get_slot_count(chest_id: StringName) -> int:
	var config: Dictionary = container_configs.get(chest_id, {})
	return maxi(int(config.get(&"slot_count", DEFAULT_SLOT_COUNT)), 1)


func get_container_title(chest_id: StringName) -> String:
	var config: Dictionary = container_configs.get(chest_id, {})
	return str(config.get(&"title", "Storage"))


func get_container_filter_id(chest_id: StringName) -> StringName:
	var config: Dictionary = container_configs.get(chest_id, {})
	return StringName(config.get(&"filter_id", FILTER_ANY))


func get_container_protection_summary(chest_id: StringName) -> String:
	match get_container_filter_id(chest_id):
		FILTER_VOLATILE_ELEMENTS:
			return "Volatile locker: accepts volatile reagents and keeps them out of your pack, but it is not weather-sealed."
		FILTER_WATER_REACTIVE_ELEMENTS:
			return "Dry Box: accepts water-reactive materials and keeps them dry even when the box sits exposed."
		_:
			return "Storage Chest: general-purpose storage. Rain protection only comes from roof cover."


func get_container_exposure_summary(chest_id: StringName, sheltered: bool) -> String:
	match get_container_filter_id(chest_id):
		FILTER_VOLATILE_ELEMENTS:
			return "Current placement: %s." % (
				"Sheltered from rain" if sheltered else "Exposed to rain"
			)
		FILTER_WATER_REACTIVE_ELEMENTS:
			return "Current placement: %s." % (
				"Sheltered, with dry seal intact"
				if sheltered
				else "Exposed, but contents stay dry inside the sealed box"
			)
		_:
			return "Current placement: %s." % (
				"Sheltered from rain" if sheltered else "Exposed to rain"
			)


func can_store_item(chest_id: StringName, item_data: Dictionary) -> bool:
	var item_id := StringName(str(item_data.get(&"id", item_data.get("id", &""))))
	if item_id.is_empty():
		return false
	var config: Dictionary = container_configs.get(chest_id, {})
	var filter_id := StringName(config.get(&"filter_id", FILTER_ANY))
	if filter_id == FILTER_ANY:
		return true
	var element_data := ElementDatabase.get_element(item_id)
	if element_data.is_empty():
		return false

	var category_name := String(element_data.get(&"category", "")).to_lower()
	match filter_id:
		FILTER_VOLATILE_ELEMENTS:
			return category_name == "volatile"
		FILTER_WATER_REACTIVE_ELEMENTS:
			var properties: Dictionary = element_data.get(&"properties", {})
			var reactivity := float(properties.get(&"reactivity", 0.0))
			return (
				(category_name == "metal" or category_name == "volatile")
				and reactivity >= 0.9
			)
		_:
			return true


func _store_item_into_slot(chest_id: StringName, item_data: Dictionary, quantity: int, chest_slot_index: int) -> void:
	ensure_container(chest_id)
	var items: Dictionary = chest_inventories[chest_id][&"items"]
	var slot_order: Array[StringName] = chest_inventories[chest_id][&"slot_order"]
	var item_id := StringName(str(item_data.get(&"id", "")))
	var target_item := get_slot_item(chest_id, chest_slot_index)

	if items.has(item_id):
		var existing: Dictionary = (items[item_id] as Dictionary).duplicate(true)
		existing[&"quantity"] = int(existing.get(&"quantity", 0)) + quantity
		items[item_id] = existing
	else:
		var stored_item := item_data.duplicate(true)
		stored_item[&"id"] = item_id
		stored_item[&"quantity"] = quantity
		items[item_id] = stored_item

	if target_item.is_empty():
		var current_index := slot_order.find(item_id)
		if current_index != -1:
			slot_order[current_index] = EMPTY_ITEM
		slot_order[chest_slot_index] = item_id

	chest_inventories[chest_id][&"items"] = items
	chest_inventories[chest_id][&"slot_order"] = slot_order


func _remove_item(chest_id: StringName, item_id: StringName, quantity: int) -> bool:
	ensure_container(chest_id)
	var items: Dictionary = chest_inventories[chest_id][&"items"]
	if not items.has(item_id):
		return false
	var stored_item: Dictionary = items[item_id]
	var current_quantity := int(stored_item.get(&"quantity", 0))
	if quantity > current_quantity:
		return false
	var remaining := current_quantity - quantity
	if remaining <= 0:
		items.erase(item_id)
		_remove_item_from_slots(chest_id, item_id)
	else:
		stored_item[&"quantity"] = remaining
		items[item_id] = stored_item
	chest_inventories[chest_id][&"items"] = items
	return true


func _remove_item_from_slots(chest_id: StringName, item_id: StringName) -> void:
	var slot_order: Array[StringName] = chest_inventories[chest_id][&"slot_order"]
	for i in range(slot_order.size()):
		if slot_order[i] == item_id:
			slot_order[i] = EMPTY_ITEM
	chest_inventories[chest_id][&"slot_order"] = slot_order


func _build_empty_slot_order(slot_count: int = DEFAULT_SLOT_COUNT) -> Array[StringName]:
	var slot_order: Array[StringName] = []
	for _i in range(maxi(slot_count, 1)):
		slot_order.append(EMPTY_ITEM)
	return slot_order


func _ensure_slot_count(chest_id: StringName) -> void:
	var slot_order: Array[StringName] = chest_inventories[chest_id].get(&"slot_order", [])
	while slot_order.size() < get_slot_count(chest_id):
		slot_order.append(EMPTY_ITEM)
	chest_inventories[chest_id][&"slot_order"] = slot_order


func _register_container_config(chest_id: StringName, config: Dictionary) -> void:
	var previous_config: Dictionary = container_configs.get(chest_id, {})
	var next_config := previous_config.duplicate(true)
	if config.has(&"slot_count"):
		next_config[&"slot_count"] = maxi(int(config.get(&"slot_count", DEFAULT_SLOT_COUNT)), 1)
	if config.has(&"title"):
		next_config[&"title"] = str(config.get(&"title", "Storage"))
	if config.has(&"filter_id"):
		next_config[&"filter_id"] = StringName(config.get(&"filter_id", FILTER_ANY))
	if next_config.is_empty():
		next_config = {
			&"slot_count": DEFAULT_SLOT_COUNT,
			&"title": "Storage",
			&"filter_id": FILTER_ANY,
		}
	container_configs[chest_id] = next_config


func _emit_changed(chest_id: StringName) -> void:
	chest_inventory_changed.emit(chest_id)
	GameManager.mark_dirty()
