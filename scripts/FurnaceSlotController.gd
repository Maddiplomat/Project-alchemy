class_name FurnaceSlotController
extends RefCounted

const GameplayData = preload("res://scripts/GameplayData.gd")

const SLOT_EMPTY_COLOR := Color(0.52, 0.55, 0.60, 1.0)

var _placeholder_textures: Dictionary = {}


func build_slot_ref(owner: Node, node_name: String) -> Dictionary:
	var panel_path := "Root/PanelContainer/MarginContainer/VBoxContainer/FurnaceRow/%s" % node_name
	var slot_path := "%s/MarginContainer/VBoxContainer" % panel_path
	return {
		&"panel": owner.get_node(NodePath(panel_path)),
		&"visual": owner.get_node(NodePath("%s/IconHolder/SlotVisual" % slot_path)),
		&"icon": owner.get_node(NodePath("%s/IconHolder/SlotVisual/ItemIcon" % slot_path)),
		&"quantity": owner.get_node(NodePath("%s/IconHolder/SlotVisual/QuantityLabel" % slot_path)),
		&"name": owner.get_node(NodePath("%s/ItemNameLabel" % slot_path)),
	}


func apply_slot_visual(slot_refs: Dictionary, slot_id: StringName, item_id: StringName, quantity: int, empty_label: String) -> void:
	var refs: Dictionary = slot_refs.get(slot_id, {})
	if refs.is_empty():
		return

	var icon: TextureRect = refs[&"icon"]
	var quantity_label: Label = refs[&"quantity"]
	var name_label: Label = refs[&"name"]
	var has_item := not item_id.is_empty() and quantity > 0

	icon.texture = _get_placeholder_texture(String(item_id)) if has_item else null
	icon.modulate = get_item_color(String(item_id)) if has_item else SLOT_EMPTY_COLOR
	quantity_label.text = "x%d" % quantity if has_item else ""
	name_label.text = get_item_label(item_id) if has_item else empty_label
	name_label.modulate = Color(0.93, 0.94, 0.96, 1.0) if has_item else Color(0.57, 0.60, 0.65, 1.0)


func get_drop_slot_id(slot_refs: Dictionary, global_mouse_position: Vector2) -> StringName:
	for slot_id: StringName in [&"input_a", &"input_b", &"fuel"]:
		var slot_ref: Dictionary = slot_refs.get(slot_id, {})
		if slot_ref.is_empty():
			continue

		var slot_visual: Control = slot_ref.get(&"visual")
		if slot_visual != null and slot_visual.get_global_rect().has_point(global_mouse_position):
			return slot_id

	return &""


func should_withdraw_from_gui_input(is_open: bool, event: InputEvent, slot_id: StringName) -> bool:
	if not is_open or slot_id == &"output":
		return false
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		return not touch_event.pressed
	if not (event is InputEventMouseButton):
		return false
	var mouse_event := event as InputEventMouseButton
	return not mouse_event.pressed and (
		mouse_event.button_index == MOUSE_BUTTON_LEFT or mouse_event.button_index == MOUSE_BUTTON_RIGHT
	)


func withdraw_slot_to_inventory(bound_furnace: Node, slot_id: StringName, action_hint_label: Label, get_item_label_callable: Callable) -> void:
	if not is_instance_valid(bound_furnace):
		return

	var slot_state: Dictionary = bound_furnace.get_fuel_state() if slot_id == &"fuel" else bound_furnace.get_input(slot_id)
	var item_id := StringName(slot_state.get(&"item_id", &""))
	var quantity := int(slot_state.get(&"quantity", 0))
	if item_id.is_empty() or quantity <= 0:
		return

	var item_data := GameplayData.elements().get_element(item_id)
	if item_data.is_empty():
		action_hint_label.text = "Cannot return %s from this slot." % get_item_label_callable.call(item_id)
		return
	if not InventoryManager.can_add_item(item_data, quantity):
		action_hint_label.text = "Inventory full. Cannot remove %s x%d." % [get_item_label_callable.call(item_id), quantity]
		return

	var removed_qty := 0
	if slot_id == &"fuel":
		if bound_furnace.has_method("remove_fuel"):
			removed_qty = int(bound_furnace.remove_fuel(quantity))
	else:
		removed_qty = int(bound_furnace.consume_input(slot_id, quantity))
	if removed_qty <= 0:
		return

	if not InventoryManager.add_item(item_data, removed_qty):
		if slot_id == &"fuel":
			bound_furnace.add_fuel(item_id, removed_qty)
		else:
			bound_furnace.set_input(slot_id, item_id, removed_qty)
		action_hint_label.text = "Inventory full. Cannot remove %s x%d." % [get_item_label_callable.call(item_id), removed_qty]
		return

	action_hint_label.text = "Removed %s x%d." % [get_item_label_callable.call(item_id), removed_qty]


func can_accept_drop_to_slot(slot_state: Dictionary, slot_id: StringName, item_id: StringName, qty: int) -> bool:
	if qty <= 0 or item_id.is_empty():
		return false
	if slot_id == &"fuel":
		var fuel_state: Dictionary = slot_state.get(slot_id, {})
		var current_fuel_id: StringName = fuel_state.get(&"item_id", &"")
		return EventBus.get_chemistry_engine().get_fuel_value(String(item_id)) > 0.0 and (
			current_fuel_id.is_empty() or current_fuel_id == item_id
		)
	if GameplayData.elements().get_element(item_id).is_empty():
		return false

	var current_slot_state: Dictionary = slot_state.get(slot_id, {})
	var current_item_id: StringName = current_slot_state.get(&"item_id", &"")
	return current_item_id.is_empty() or current_item_id == item_id


func get_item_label(item_id: StringName) -> String:
	if item_id.is_empty():
		return ""

	var element_data := GameplayData.elements().get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", item_id))

	return String(item_id).replace("_", " ").capitalize()


func get_item_color(item_id: String) -> Color:
	match item_id:
		"wood":
			return Color.BURLYWOOD
		"stone":
			return Color.GRAY
		"iron":
			return Color.SILVER
		"steel":
			return Color(0.70, 0.76, 0.82, 1.0)
		"pure_carbon":
			return Color(0.29, 0.31, 0.35, 1.0)
		"charcoal":
			return Color(0.18, 0.19, 0.21, 1.0)
		"slag":
			return Color(0.43, 0.18, 0.16, 1.0)
		"iron_axe":
			return Color(0.71, 0.73, 0.77, 1.0)
		"steel_axe":
			return Color(0.82, 0.85, 0.90, 1.0)
		"iron_pickaxe":
			return Color(0.76, 0.82, 0.88, 1.0)
		"steel_pickaxe":
			return Color(0.86, 0.90, 0.95, 1.0)
		"steel_sword":
			return Color(0.82, 0.85, 0.90, 1.0)
		_:
			return Color.WHITE


func _get_placeholder_texture(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null

	if _placeholder_textures.has(item_id):
		return _placeholder_textures[item_id]

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.WHITE)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 96
	texture.height = 96
	_placeholder_textures[item_id] = texture
	return texture
