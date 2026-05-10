extends Node

signal inventory_changed
signal weight_changed(total_weight: float, carry_capacity: float)
signal held_item_changed(item_id: String)

const DEFAULT_SLOT_COUNT := 20
const carry_capacity := 20.0

# Dictionary of {element_id: {quantity: int, purity: float}}
var items: Dictionary = {}
var slot_order: Array[String] = []
var held_item_id := ""
var manual_selection := false
var total_weight := 0.0

func _ready() -> void:
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	_refresh_total_weight()
	_sync_held_item()
	weight_changed.emit(total_weight, carry_capacity)

func add_element(id: String, qty: int, purity: float) -> void:
	if items.has(id):
		_assign_item_to_slot(id)
		var current = items[id]
		# Calculate average purity weighted by quantity
		var total_qty = current.quantity + qty
		var new_purity = (current.purity * current.quantity + purity * qty) / total_qty
		
		items[id].quantity = total_qty
		items[id].purity = new_purity
	else:
		items[id] = {
			"quantity": qty,
			"purity": purity
		}
		_assign_item_to_slot(id)
	
	_sync_held_item()
	_refresh_total_weight()
	weight_changed.emit(total_weight, carry_capacity)
	inventory_changed.emit()

func remove_element(id: String, qty: int) -> void:
	if items.has(id):
		items[id].quantity -= qty
		if items[id].quantity <= 0:
			items.erase(id)
			_remove_item_from_slots(id)
		
		_sync_held_item()
		_refresh_total_weight()
		weight_changed.emit(total_weight, carry_capacity)
		inventory_changed.emit()

func get_stack(id: String) -> Dictionary:
	return items.get(id, {"quantity": 0, "purity": 0.0})

func get_all_items() -> Dictionary:
	var ordered_items := {}
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	for item_id in slot_order:
		if item_id != "" and items.has(item_id):
			ordered_items[item_id] = items[item_id]
	
	for item_id in items.keys():
		if not ordered_items.has(item_id):
			ordered_items[item_id] = items[item_id]
	
	return ordered_items

func get_slot_item(slot_index: int) -> Dictionary:
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	if slot_index < 0 or slot_index >= slot_order.size():
		return {}
	
	var item_id := slot_order[slot_index]
	if item_id == "" or not items.has(item_id):
		return {}
	
	var stack: Dictionary = items[item_id].duplicate(true)
	stack["id"] = item_id
	return stack

func get_held_item_id() -> String:
	return held_item_id

func get_held_item() -> Dictionary:
	if held_item_id == "" or not items.has(held_item_id):
		return {}
	
	var stack: Dictionary = items[held_item_id].duplicate(true)
	stack["id"] = held_item_id
	return stack

func is_over_capacity() -> bool:
	return total_weight > carry_capacity

func set_held_item(id: String, manual: bool = false) -> bool:
	if id == held_item_id:
		manual_selection = manual or manual_selection
		return true
	if id != "" and not items.has(id):
		return false
	
	held_item_id = id
	manual_selection = manual
	held_item_changed.emit(held_item_id)
	return true

func select_slot(slot_index: int) -> void:
	var item = get_slot_item(slot_index)
	if not item.is_empty():
		set_held_item(item.id, true)

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
	weight_changed.emit(total_weight, carry_capacity)
	inventory_changed.emit()

func _assign_item_to_slot(id: String) -> void:
	_ensure_slot_count(DEFAULT_SLOT_COUNT)
	if slot_order.has(id):
		return
	
	var empty_index := slot_order.find("")
	if empty_index == -1:
		slot_order.append(id)
	else:
		slot_order[empty_index] = id

func _remove_item_from_slots(id: String) -> void:
	for i in range(slot_order.size()):
		if slot_order[i] == id:
			slot_order[i] = ""

func _ensure_slot_count(count: int) -> void:
	while slot_order.size() < count:
		slot_order.append("")

func _refresh_total_weight() -> void:
	total_weight = 0.0
	for item_id in items.keys():
		var stack: Dictionary = items[item_id]
		var quantity := int(stack.get("quantity", 0))
		if quantity <= 0:
			continue

		var element_data := ElementDatabase.get_element(StringName(item_id))
		total_weight += float(element_data.get("weight", 0.0)) * quantity

func _sync_held_item() -> void:
	if manual_selection and held_item_id != "" and items.has(held_item_id):
		return
	
	manual_selection = false
	for item_id in slot_order:
		if item_id != "" and items.has(item_id):
			set_held_item(item_id, false)
			return
	
	set_held_item("", false)
