extends Node

signal inventory_changed

# Dictionary of {element_id: {quantity: int, purity: float}}
var items: Dictionary = {}

func add_element(id: String, qty: int, purity: float):
	if items.has(id):
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
	
	inventory_changed.emit()

func remove_element(id: String, qty: int):
	if items.has(id):
		items[id].quantity -= qty
		if items[id].quantity <= 0:
			items.erase(id)
		
		inventory_changed.emit()

func get_stack(id: String) -> Dictionary:
	return items.get(id, {"quantity": 0, "purity": 0.0})

func get_all_items() -> Dictionary:
	return items
