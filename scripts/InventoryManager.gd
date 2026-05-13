extends Node

signal inventory_changed
signal item_added(item_id: StringName, quantity: int, total_quantity: int)
signal item_removed(item_id: StringName, quantity: int, remaining_quantity: int)
signal item_quantity_changed(item_id: StringName, quantity: int)
signal held_item_changed(item_id: StringName)
signal capacity_changed(current_weight: float, max_weight: float)
signal weight_changed(total_weight: float, carry_capacity: float)
signal volatile_risk_changed(risk_item_ids: Array[StringName])

const DEFAULT_SLOT_COUNT := 20
const DEFAULT_ITEM_WEIGHT := 1.0
const DEFAULT_ITEM_PURITY := 1.0
const DEFAULT_ITEM_DURABILITY := 1.0
const DEFAULT_ITEM_MAX_DURABILITY := 1.0
const NO_HELD_ITEM := &""
const carry_capacity := 20.0

enum InventoryItemCategory { GENERIC, ELEMENT, TOOL, CRAFTED, CONSUMABLE }
enum InventoryRiskLevel { NONE, LOW, MEDIUM, HIGH, EXTREME }

var items: Dictionary[StringName, Dictionary] = {}
var max_weight: float = carry_capacity
var current_weight: float = 0.0
var total_weight: float = 0.0
var slot_order: Array[StringName] = []
var held_item_id: StringName = NO_HELD_ITEM
var manual_selection := false
var volatile_risk_item_ids: Array[StringName] = []


func _ready() -> void:
	_ensure_slot_count(DEFAULT_SLOT_COUNT)


func can_add_item(item_data: Dictionary, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var item_id := _get_item_id(item_data)
	if item_id.is_empty():
		return false

	var added_weight := _get_stack_unit_weight(item_id, item_data) * float(quantity)
	if current_weight < max_weight:
		return true

	return current_weight + added_weight <= max_weight


func add_item(item_data: Dictionary, quantity: int = 1) -> bool:
	if not can_add_item(item_data, quantity):
		return false

	var item_id := _get_item_id(item_data)
	var existing_item := get_item(item_id)
	var previous_quantity: int = existing_item.get(&"quantity", 0)
	var total_quantity := previous_quantity + quantity

	var stored_item := _normalize_item_data(item_data, total_quantity)
	items[item_id] = stored_item
	current_weight += _get_stack_unit_weight(item_id, stored_item) * float(quantity)
	_assign_item_to_slot(item_id)
	_sync_held_item()

	item_added.emit(item_id, quantity, total_quantity)
	item_quantity_changed.emit(item_id, total_quantity)
	_emit_inventory_state_changed()
	return true


func receive_world_pickup(item_data: Dictionary, quantity: int = 1) -> bool:
	return add_item(item_data, quantity)


func remove_item(item_id: StringName, quantity: int = 1) -> bool:
	if quantity <= 0 or not items.has(item_id):
		return false

	var stored_item := items[item_id]
	var previous_quantity: int = stored_item.get(&"quantity", 0)
	if quantity > previous_quantity:
		return false

	var remaining_quantity := previous_quantity - quantity
	current_weight = maxf(0.0, current_weight - (_get_stack_unit_weight(item_id, stored_item) * float(quantity)))

	if remaining_quantity <= 0:
		items.erase(item_id)
		_remove_item_from_slots(item_id)
		if held_item_id == item_id:
			set_held_item(NO_HELD_ITEM)
	else:
		stored_item[&"quantity"] = remaining_quantity
		items[item_id] = stored_item

	_sync_held_item()

	item_removed.emit(item_id, quantity, remaining_quantity)
	item_quantity_changed.emit(item_id, remaining_quantity)
	_emit_inventory_state_changed()
	return true


func has_item(item_id: StringName, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true

	return get_quantity(item_id) >= quantity


func get_item(item_id: StringName) -> Dictionary:
	if not items.has(item_id):
		return {}

	return items[item_id].duplicate(true)


func get_quantity(item_id: StringName) -> int:
	if not items.has(item_id):
		return 0

	return items[item_id].get(&"quantity", 0)


func get_stack(id: String) -> Dictionary:
	return items.get(StringName(id), {"quantity": 0, "purity": 0.0})


func get_all_items() -> Dictionary:
	var ordered_items := {}
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	for item_id: StringName in slot_order:
		if not item_id.is_empty() and items.has(item_id):
			ordered_items[String(item_id)] = items[item_id]

	for item_id: StringName in items.keys():
		if not ordered_items.has(String(item_id)):
			ordered_items[String(item_id)] = items[item_id]

	return ordered_items


func get_slot_item(slot_index: int) -> Dictionary:
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	if slot_index < 0 or slot_index >= slot_order.size():
		return {}

	var item_id := slot_order[slot_index]
	if item_id.is_empty() or not items.has(item_id):
		return {}

	var stack: Dictionary = items[item_id].duplicate(true)
	stack["id"] = String(item_id)
	return stack


func get_held_item_id() -> String:
	return String(held_item_id)


func get_held_item() -> Dictionary:
	if held_item_id.is_empty() or not items.has(held_item_id):
		return {}

	var stack: Dictionary = items[held_item_id].duplicate(true)
	stack["id"] = String(held_item_id)
	return stack


func is_over_capacity() -> bool:
	return total_weight > max_weight


func lose_random_item() -> bool:
	if items.is_empty():
		return false
	
	var item_ids := items.keys()
	var random_id = item_ids[randi() % item_ids.size()]
	return remove_item(random_id, 1)


func set_held_item(item_id: StringName, manual: bool = false) -> bool:
	if item_id == held_item_id:
		manual_selection = manual or manual_selection
		return true

	if not item_id.is_empty() and not items.has(item_id):
		return false

	held_item_id = item_id
	manual_selection = manual
	held_item_changed.emit(held_item_id)
	return true


func select_slot(slot_index: int) -> void:
	var item = get_slot_item(slot_index)
	if not item.is_empty():
		set_held_item(StringName(str(item.get("id", ""))), true)


func swap_slots(from_slot: int, to_slot: int) -> void:
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	if from_slot < 0 or from_slot >= slot_order.size():
		return
	if to_slot < 0 or to_slot >= slot_order.size():
		return
	if from_slot == to_slot:
		return

	var from_item := slot_order[from_slot]
	slot_order[from_slot] = slot_order[to_slot]
	slot_order[to_slot] = from_item
	inventory_changed.emit()


func clear_inventory() -> void:
	if items.is_empty() and is_zero_approx(current_weight) and held_item_id.is_empty():
		return

	items.clear()
	slot_order.fill(NO_HELD_ITEM)
	current_weight = 0.0
	total_weight = 0.0
	held_item_id = NO_HELD_ITEM
	manual_selection = false
	held_item_changed.emit(held_item_id)
	_emit_inventory_state_changed()


func add_element(id: String, qty: int, purity: float) -> bool:
	var item_id := StringName(id)
	var item_data := ElementDatabase.get_element(item_id)
	if item_data.is_empty():
		return false

	item_data[&"purity"] = purity
	item_data[&"category"] = InventoryItemCategory.ELEMENT
	item_data[&"risk_level"] = _to_inventory_risk_level(item_data.get(&"carrier_risk"))
	return add_item(item_data, qty)


func remove_element(id: String, qty: int) -> void:
	remove_item(StringName(id), qty)


func degrade_item(item_id: StringName, amount: float) -> bool:
	if amount <= 0.0 or not items.has(item_id):
		return false

	var stored_item := items[item_id]
	if stored_item.get(&"durability") == null:
		return false

	var current_durability := float(stored_item.get(&"durability", DEFAULT_ITEM_DURABILITY))
	var next_durability := clampf(current_durability - amount, 0.0, float(stored_item.get(&"max_durability", DEFAULT_ITEM_MAX_DURABILITY)))
	if is_equal_approx(next_durability, current_durability):
		return false

	stored_item[&"durability"] = next_durability
	if next_durability <= 0.0:
		return remove_item(item_id, stored_item.get(&"quantity", 1))

	items[item_id] = stored_item
	_emit_inventory_state_changed()
	return true


func set_max_weight(value: float) -> void:
	var clamped_weight := maxf(0.0, value)
	if is_equal_approx(max_weight, clamped_weight):
		return

	max_weight = clamped_weight
	_emit_inventory_state_changed()


func get_capacity_ratio() -> float:
	if is_zero_approx(max_weight):
		return 1.0

	return clampf(current_weight / max_weight, 0.0, 1.0)


func get_items() -> Dictionary[StringName, Dictionary]:
	var result: Dictionary[StringName, Dictionary] = {}
	for item_id: StringName in items:
		result[item_id] = items[item_id].duplicate(true)

	return result


func get_volatile_risk_item_ids() -> Array[StringName]:
	return volatile_risk_item_ids.duplicate()


func _emit_inventory_state_changed() -> void:
	_recalculate_weight()
	_recalculate_volatile_risk()
	capacity_changed.emit(current_weight, max_weight)
	weight_changed.emit(total_weight, max_weight)
	inventory_changed.emit()
	_mark_game_dirty()


func _normalize_item_data(item_data: Dictionary, quantity: int) -> Dictionary:
	var normalized := item_data.duplicate(true)
	normalized[&"id"] = _get_item_id(item_data)
	normalized[&"quantity"] = quantity
	normalized[&"unit_weight"] = _get_unit_weight(item_data)
	normalized[&"purity"] = _get_purity(item_data)

	if not normalized.has(&"risk_level"):
		normalized[&"risk_level"] = InventoryRiskLevel.NONE

	if not normalized.has(&"category"):
		normalized[&"category"] = InventoryItemCategory.GENERIC

	var category: int = normalized.get(&"category", InventoryItemCategory.GENERIC)
	var is_raw_element := category == InventoryItemCategory.ELEMENT
	var max_durability = normalized.get(&"max_durability")
	if is_raw_element:
		normalized[&"durability"] = null
		normalized[&"max_durability"] = null
	else:
		if max_durability == null:
			max_durability = DEFAULT_ITEM_MAX_DURABILITY
		max_durability = maxf(0.0, float(max_durability))
		normalized[&"max_durability"] = max_durability

		var durability = normalized.get(&"durability")
		if durability == null:
			durability = max_durability
		normalized[&"durability"] = clampf(float(durability), 0.0, max_durability)

	return normalized


func _get_item_id(item_data: Dictionary) -> StringName:
	return item_data.get(&"id", &"")


func _get_unit_weight(item_data: Dictionary) -> float:
	return maxf(0.0, item_data.get(&"unit_weight", item_data.get(&"weight", DEFAULT_ITEM_WEIGHT)))


func _get_stack_unit_weight(item_id: StringName, item_data: Dictionary) -> float:
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return maxf(0.0, float(element_data.get(&"weight", DEFAULT_ITEM_WEIGHT)))

	return _get_unit_weight(item_data)


func _get_purity(item_data: Dictionary) -> float:
	return clampf(item_data.get(&"purity", DEFAULT_ITEM_PURITY), 0.0, 1.0)


func _to_inventory_risk_level(risk_level_name) -> int:
	match str(risk_level_name).to_lower():
		"low":
			return InventoryRiskLevel.LOW
		"medium":
			return InventoryRiskLevel.MEDIUM
		"high":
			return InventoryRiskLevel.HIGH
		"extreme":
			return InventoryRiskLevel.EXTREME
		_:
			return InventoryRiskLevel.NONE


func _recalculate_weight() -> void:
	var recalculated_weight := 0.0
	for item_id: StringName in items:
		var stored_item := items[item_id]
		var quantity: int = stored_item.get(&"quantity", 0)
		recalculated_weight += _get_stack_unit_weight(item_id, stored_item) * float(quantity)

	total_weight = recalculated_weight
	current_weight = recalculated_weight


func _recalculate_volatile_risk() -> void:
	var previous_risk_item_ids := volatile_risk_item_ids.duplicate()
	volatile_risk_item_ids.clear()

	for item_id: StringName in items:
		var stored_item := items[item_id]
		if _is_risky_item(stored_item):
			volatile_risk_item_ids.append(item_id)

	if previous_risk_item_ids != volatile_risk_item_ids:
		volatile_risk_changed.emit(volatile_risk_item_ids.duplicate())


func _assign_item_to_slot(item_id: StringName) -> void:
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	if slot_order.has(item_id):
		return

	var empty_index := slot_order.find(NO_HELD_ITEM)
	if empty_index == -1:
		slot_order.append(item_id)
	else:
		slot_order[empty_index] = item_id


func _remove_item_from_slots(item_id: StringName) -> void:
	for i in range(slot_order.size()):
		if slot_order[i] == item_id:
			slot_order[i] = NO_HELD_ITEM


func _ensure_slot_count(count: int) -> void:
	while slot_order.size() < count:
		slot_order.append(NO_HELD_ITEM)


func _sync_held_item() -> void:
	if manual_selection and not held_item_id.is_empty() and items.has(held_item_id):
		return

	manual_selection = false
	for item_id: StringName in slot_order:
		if not item_id.is_empty() and items.has(item_id):
			set_held_item(item_id, false)
			return

	set_held_item(NO_HELD_ITEM, false)


func _is_risky_item(item_data: Dictionary) -> bool:
	var risk_level: int = item_data.get(&"risk_level", InventoryRiskLevel.NONE)
	if risk_level >= InventoryRiskLevel.MEDIUM:
		return true

	var category: int = item_data.get(&"category", InventoryItemCategory.GENERIC)
	return category == InventoryItemCategory.ELEMENT and risk_level >= InventoryRiskLevel.LOW


func _mark_game_dirty() -> void:
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").mark_dirty()
