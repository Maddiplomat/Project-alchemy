class_name FurnaceSlotUI
extends Node

const FurnaceSlotControllerScript = preload("res://scripts/FurnaceSlotController.gd")

signal withdraw_requested(slot_id: StringName)

var slot_refs: Dictionary[StringName, Dictionary] = {}
var _controller := FurnaceSlotControllerScript.new()
var _is_open_provider: Callable


func configure(owner_ui: CanvasLayer, is_open_provider: Callable) -> void:
	_is_open_provider = is_open_provider
	slot_refs = {
		&"input_a": _controller.build_slot_ref(owner_ui, "InputSlotA"),
		&"input_b": _controller.build_slot_ref(owner_ui, "InputSlotB"),
		&"fuel": _controller.build_slot_ref(owner_ui, "FuelSlot"),
		&"output": _controller.build_slot_ref(owner_ui, "OutputSlot"),
	}
	for slot_id: StringName in slot_refs.keys():
		var slot_visual: Control = slot_refs[slot_id].get(&"visual")
		var callback := _on_slot_gui_input.bind(slot_id)
		if slot_visual != null and not slot_visual.gui_input.is_connected(callback):
			slot_visual.gui_input.connect(callback)


func reset_visuals() -> void:
	apply_visual(&"input_a", &"", 0, "No material")
	apply_visual(&"input_b", &"", 0, "No material")
	apply_visual(&"fuel", &"", 0, "Fuel item")
	apply_visual(&"output", &"", 0, "Awaiting recipe")


func apply_visual(slot_id: StringName, item_id: StringName, quantity: int, empty_label: String) -> void:
	_controller.apply_slot_visual(slot_refs, slot_id, item_id, quantity, empty_label)


func get_drop_slot_id(global_mouse_position: Vector2) -> StringName:
	return _controller.get_drop_slot_id(slot_refs, global_mouse_position)


func can_accept_drop(slot_state: Dictionary, slot_id: StringName, item_id: StringName, quantity: int) -> bool:
	return _controller.can_accept_drop_to_slot(slot_state, slot_id, item_id, quantity)


func withdraw_to_inventory(bound_furnace: Node, slot_id: StringName, action_hint_label: Label) -> void:
	_controller.withdraw_slot_to_inventory(bound_furnace, slot_id, action_hint_label, Callable(self, "get_item_label"))


func get_item_label(item_id: StringName) -> String:
	return _controller.get_item_label(item_id)


func _on_slot_gui_input(event: InputEvent, slot_id: StringName) -> void:
	var is_open := bool(_is_open_provider.call()) if _is_open_provider.is_valid() else false
	if not _controller.should_withdraw_from_gui_input(is_open, event, slot_id):
		return
	withdraw_requested.emit(slot_id)
	get_viewport().set_input_as_handled()
