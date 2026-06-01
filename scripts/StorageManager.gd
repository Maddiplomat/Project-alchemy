extends Node

signal chest_inventory_changed(chest_id: StringName)

const SLOT_COUNT := 20
const EMPTY_ITEM := &""

var chest_inventories: Dictionary = {}


func ensure_chest(chest_id: StringName) -> void:
	if chest_id.is_empty():
		return
	if chest_inventories.has(chest_id):
		_ensure_slot_count(chest_id)
		return
	chest_inventories[chest_id] = {
		&"items": {},
		&"slot_order": _build_empty_slot_order(),
	}


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
	ensure_chest(chest_id)
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
	ensure_chest(chest_id)
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
	ensure_chest(chest_id)
	var player_item := InventoryManager.get_slot_item(player_slot_index)
	if player_item.is_empty():
		return false
	var item_id := StringName(str(player_item.get(&"id", "")))
	var available_quantity := int(player_item.get(&"quantity", 0))
	quantity = mini(quantity, available_quantity)
	if item_id.is_empty() or quantity <= 0:
		return false

	var target_item := get_slot_item(chest_id, chest_slot_index)
	if not target_item.is_empty() and StringName(str(target_item.get(&"id", ""))) != item_id:
		return false

	if not InventoryManager.remove_item(item_id, quantity):
		return false

	_store_item_into_slot(chest_id, player_item, quantity, chest_slot_index)
	_emit_changed(chest_id)
	return true


func withdraw_to_player(chest_id: StringName, chest_slot_index: int, player_slot_index: int, quantity: int) -> bool:
	ensure_chest(chest_id)
	var chest_item := get_slot_item(chest_id, chest_slot_index)
	if chest_item.is_empty():
		return false
	var item_id := StringName(str(chest_item.get(&"id", "")))
	var available_quantity := int(chest_item.get(&"quantity", 0))
	quantity = mini(quantity, available_quantity)
	if item_id.is_empty() or quantity <= 0:
		return false

	var target_item := InventoryManager.get_slot_item(player_slot_index)
	if not target_item.is_empty() and StringName(str(target_item.get(&"id", ""))) != item_id:
		return false
	if not InventoryManager.can_add_item(chest_item, quantity):
		return false

	if not _remove_item(chest_id, item_id, quantity):
		return false

	if not InventoryManager.add_item(chest_item, quantity):
		_store_item_into_slot(chest_id, chest_item, quantity, chest_slot_index)
		_emit_changed(chest_id)
		return false

	if target_item.is_empty():
		InventoryManager.move_item_to_slot(item_id, player_slot_index)

	_emit_changed(chest_id)
	return true


func export_to_world_save_data(world_save_data) -> void:
	if world_save_data == null:
		return
	world_save_data.chest_inventories = {}
	for chest_id: StringName in chest_inventories.keys():
		var items: Dictionary = chest_inventories[chest_id][&"items"]
		var slot_order: Array[StringName] = chest_inventories[chest_id][&"slot_order"]
		var serialized_items := {}
		for item_id: StringName in items.keys():
			serialized_items[String(item_id)] = (items[item_id] as Dictionary).duplicate(true)
		var serialized_slots: Array[String] = []
		for slot_item_id: StringName in slot_order:
			serialized_slots.append(String(slot_item_id))
		world_save_data.chest_inventories[String(chest_id)] = {
			&"items": serialized_items,
			&"slot_order": serialized_slots,
		}


func _store_item_into_slot(chest_id: StringName, item_data: Dictionary, quantity: int, chest_slot_index: int) -> void:
	ensure_chest(chest_id)
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
	ensure_chest(chest_id)
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


func _build_empty_slot_order() -> Array[StringName]:
	var slot_order: Array[StringName] = []
	for _i in range(SLOT_COUNT):
		slot_order.append(EMPTY_ITEM)
	return slot_order


func _ensure_slot_count(chest_id: StringName) -> void:
	var slot_order: Array[StringName] = chest_inventories[chest_id].get(&"slot_order", [])
	while slot_order.size() < SLOT_COUNT:
		slot_order.append(EMPTY_ITEM)
	chest_inventories[chest_id][&"slot_order"] = slot_order


func _emit_changed(chest_id: StringName) -> void:
	chest_inventory_changed.emit(chest_id)
	GameManager.mark_dirty()
