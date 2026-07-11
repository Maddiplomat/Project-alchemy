extends CanvasLayer

signal ui_closed

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")
const DEFAULT_STORAGE_SLOT_COUNT := 20
const SLOT_TOUCH_SIZE := Vector2(82.0, 82.0)

enum QuantityAction {
	NONE,
	PLAYER_TO_CHEST,
	CHEST_TO_PLAYER,
}

@onready var root: Control = $Root
@onready var backdrop: ColorRect = $Root/Backdrop
@onready var panel: PanelContainer = $Root/StoragePanel
@onready var title_label: Label = $Root/StoragePanel/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $Root/StoragePanel/MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var info_label: Label = $Root/StoragePanel/MarginContainer/VBoxContainer/InfoLabel
@onready var player_grid: GridContainer = $Root/StoragePanel/MarginContainer/VBoxContainer/PanelContent/PlayerColumn/PlayerGrid
@onready var chest_column: VBoxContainer = $Root/StoragePanel/MarginContainer/VBoxContainer/PanelContent/ChestColumn
@onready var chest_grid: GridContainer = $Root/StoragePanel/MarginContainer/VBoxContainer/PanelContent/ChestColumn/ChestGrid
@onready var player_weight_label: Label = $Root/StoragePanel/MarginContainer/VBoxContainer/PanelContent/PlayerColumn/WeightLabel
@onready var chest_title_label: Label = $Root/StoragePanel/MarginContainer/VBoxContainer/PanelContent/ChestColumn/ChestTitle
@onready var selection_label: Label = $Root/StoragePanel/MarginContainer/VBoxContainer/ActionPanel/MarginContainer/VBoxContainer/SelectionLabel
@onready var move_to_chest_button: Button = $Root/StoragePanel/MarginContainer/VBoxContainer/ActionPanel/MarginContainer/VBoxContainer/ActionButtons/MoveToChestButton
@onready var move_to_pack_button: Button = $Root/StoragePanel/MarginContainer/VBoxContainer/ActionPanel/MarginContainer/VBoxContainer/ActionButtons/MoveToPackButton
@onready var transfer_all_button: Button = $Root/StoragePanel/MarginContainer/VBoxContainer/ActionPanel/MarginContainer/VBoxContainer/ActionButtons/TransferAllButton
@onready var split_button: Button = $Root/StoragePanel/MarginContainer/VBoxContainer/ActionPanel/MarginContainer/VBoxContainer/ActionButtons/SplitButton
@onready var action_hint_label: Label = $Root/StoragePanel/MarginContainer/VBoxContainer/ActionPanel/MarginContainer/VBoxContainer/ActionHintLabel
@onready var quantity_modal: PanelContainer = $Root/QuantityModal
@onready var quantity_summary_label: Label = $Root/QuantityModal/MarginContainer/VBoxContainer/QuantitySummaryLabel
@onready var quantity_value_label: Label = $Root/QuantityModal/MarginContainer/VBoxContainer/StepperRow/QuantityValueLabel
@onready var minus_button: Button = $Root/QuantityModal/MarginContainer/VBoxContainer/StepperRow/MinusButton
@onready var plus_button: Button = $Root/QuantityModal/MarginContainer/VBoxContainer/StepperRow/PlusButton
@onready var quantity_cancel_button: Button = $Root/QuantityModal/MarginContainer/VBoxContainer/ModalButtons/CancelButton
@onready var quantity_confirm_button: Button = $Root/QuantityModal/MarginContainer/VBoxContainer/ModalButtons/ConfirmButton

var chest_id: StringName = &""
var _storage_context: Dictionary = {}
var _storage_status_label: Label = null
var _storage_detail_label: Label = null
var _selected_container := ""
var _selected_slot_index := -1
var _drag_origin_index := -1
var _drag_origin_container := ""
var _drag_pointer_position := Vector2.ZERO
var _drag_ghost: TextureRect = null
var _drag_quantity := 0
var _drag_source_quantity := 0
var _quantity_action := QuantityAction.NONE
var _quantity_value := 1


func _ready() -> void:
	layer = 11
	root.visible = true
	panel.visible = false
	quantity_modal.visible = false
	backdrop.visible = false
	_ensure_grid_slot_count(player_grid, InventoryManager.DEFAULT_SLOT_COUNT, "player")
	_ensure_grid_slot_count(chest_grid, DEFAULT_STORAGE_SLOT_COUNT, "chest")
	_ensure_storage_info_labels()
	close_button.pressed.connect(close_ui)
	move_to_chest_button.pressed.connect(_on_move_to_chest_pressed)
	move_to_pack_button.pressed.connect(_on_move_to_pack_pressed)
	transfer_all_button.pressed.connect(_on_transfer_all_pressed)
	split_button.pressed.connect(_on_split_pressed)
	minus_button.pressed.connect(func() -> void: _adjust_quantity(-1))
	plus_button.pressed.connect(func() -> void: _adjust_quantity(1))
	quantity_cancel_button.pressed.connect(_close_quantity_modal)
	quantity_confirm_button.pressed.connect(_confirm_quantity_modal)
	InventoryManager.inventory_changed.connect(_refresh_all.unbind(1))
	InventoryManager.active_slot_changed.connect(_refresh_all.unbind(1))
	InventoryManager.weight_changed.connect(_on_weight_changed)
	StorageManager.chest_inventory_changed.connect(_on_chest_inventory_changed)
	get_viewport().size_changed.connect(_layout_panel)
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)
	_refresh_action_panel()
	_layout_panel()


func bind_chest(bound_chest_id: StringName) -> void:
	bind_storage(bound_chest_id, {})


func bind_storage(bound_chest_id: StringName, context: Dictionary = {}) -> void:
	chest_id = bound_chest_id
	_storage_context = context.duplicate(true)
	StorageManager.ensure_container(chest_id)
	title_label.text = StorageManager.get_container_title(chest_id)
	var title := StorageManager.get_container_title(chest_id)
	chest_title_label.text = "%s %s" % [title, String(chest_id).substr(0, 8)] if title == "Storage Chest" else title
	_refresh_storage_info()
	_refresh_all()


func open_ui() -> void:
	panel.visible = true
	backdrop.visible = true
	_layout_panel()
	_refresh_storage_info()
	_refresh_all()


func close_ui() -> void:
	_cancel_drag()
	_close_quantity_modal()
	panel.visible = false
	backdrop.visible = false
	_selected_container = ""
	_selected_slot_index = -1
	_refresh_action_panel()
	ui_closed.emit()


func is_open() -> bool:
	return panel.visible


func _input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_BACK or key_event.is_action_pressed("interact"):
			close_ui()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _is_dragging():
		var release_position := get_viewport().get_mouse_position()
		var drop_target := _get_drop_target(release_position)
		_finish_drag(String(drop_target.get(&"container", "")), int(drop_target.get(&"slot_index", -1)), release_position)


func _process(_delta: float) -> void:
	if _drag_ghost != null:
		_drag_ghost.global_position = _get_pointer_screen_position() - (_drag_ghost.size / 2.0)


func _layout_panel() -> void:
	if panel == null:
		return
	var viewport_rect := get_viewport().get_visible_rect()
	if MobileInputRouter != null and MobileInputRouter.prefers_touch_controls():
		panel.offset_left = 16.0
		panel.offset_top = 16.0
		panel.offset_right = -16.0
		panel.offset_bottom = -16.0
	else:
		panel.offset_left = maxf(60.0, viewport_rect.size.x * 0.12)
		panel.offset_top = maxf(36.0, viewport_rect.size.y * 0.08)
		panel.offset_right = -maxf(60.0, viewport_rect.size.x * 0.12)
		panel.offset_bottom = -maxf(36.0, viewport_rect.size.y * 0.08)


func _build_grid(target_grid: GridContainer, container_name: String, start_index: int, count: int) -> void:
	for i in range(count):
		var slot := SLOT_SCENE.instantiate() as InventorySlot
		target_grid.add_child(slot)
		slot.slot_index = start_index + i
		slot.custom_minimum_size = SLOT_TOUCH_SIZE
		slot.drag_started.connect(_on_slot_drag_started.bind(container_name))
		slot.drag_released.connect(_on_slot_drag_released.bind(container_name))
		slot.clicked.connect(_on_slot_clicked.bind(container_name))
		slot.long_pressed.connect(_on_slot_long_pressed.bind(container_name))


func _ensure_grid_slot_count(target_grid: GridContainer, count: int, container_name: String) -> void:
	var current_count := target_grid.get_child_count()
	if current_count < count:
		_build_grid(target_grid, container_name, current_count, count - current_count)
	elif current_count > count:
		for child_index in range(current_count - 1, count - 1, -1):
			var child := target_grid.get_child(child_index)
			target_grid.remove_child(child)
			child.free()
	for child_index in range(target_grid.get_child_count()):
		var slot := target_grid.get_child(child_index) as InventorySlot
		slot.slot_index = child_index
		slot.custom_minimum_size = SLOT_TOUCH_SIZE


func _refresh_all(_unused = null) -> void:
	if chest_id.is_empty():
		return
	_ensure_grid_slot_count(chest_grid, StorageManager.get_slot_count(chest_id), "chest")
	_refresh_storage_info()
	_refresh_player_grid()
	_refresh_chest_grid()
	_refresh_action_panel()


func _refresh_player_grid() -> void:
	var active_index := InventoryManager.active_slot_index
	for i in range(player_grid.get_child_count()):
		var slot := player_grid.get_child(i) as InventorySlot
		var data := InventoryManager.get_slot_data(i)
		slot.is_equipped = i == active_index and data.item_id != &""
		if data.item_id == &"":
			slot.clear()
		else:
			slot.update_slot(String(data.item_id), data.quantity, data.purity, null, null)


func _refresh_chest_grid() -> void:
	for i in range(chest_grid.get_child_count()):
		var slot := chest_grid.get_child(i) as InventorySlot
		var data := StorageManager.get_slot_item(chest_id, i)
		slot.is_equipped = false
		if data.is_empty():
			slot.clear()
		else:
			slot.update_slot(String(data.get(&"id", "")), int(data.get(&"quantity", 0)), float(data.get(&"purity", 1.0)), data.get(&"durability"), data.get(&"max_durability"))


func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	player_weight_label.text = "%.1f / %.1f kg" % [total_weight, carry_capacity]


func _ensure_storage_info_labels() -> void:
	if chest_column == null or _storage_status_label != null:
		return
	_storage_status_label = Label.new()
	_storage_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_storage_status_label.modulate = Color(0.94, 0.92, 0.78, 1.0)
	chest_column.add_child(_storage_status_label)
	chest_column.move_child(_storage_status_label, chest_grid.get_index())
	_storage_detail_label = Label.new()
	_storage_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_storage_detail_label.modulate = Color(0.78, 0.84, 0.90, 1.0)
	chest_column.add_child(_storage_detail_label)
	chest_column.move_child(_storage_detail_label, chest_grid.get_index())


func _refresh_storage_info() -> void:
	if chest_id.is_empty() or _storage_status_label == null or _storage_detail_label == null:
		return
	var sheltered := bool(_storage_context.get(&"sheltered", false))
	_storage_status_label.text = StorageManager.get_container_protection_summary(chest_id)
	_storage_detail_label.text = StorageManager.get_container_exposure_summary(chest_id, sheltered)


func _on_chest_inventory_changed(changed_chest_id: StringName) -> void:
	if changed_chest_id != chest_id:
		return
	_refresh_chest_grid()
	_refresh_action_panel()


func _on_slot_clicked(slot_index: int, container_name: String) -> void:
	_selected_container = container_name
	_selected_slot_index = slot_index
	if container_name == "player":
		InventoryManager.set_active_slot(slot_index)
	_refresh_action_panel()


func _on_slot_long_pressed(slot_index: int, container_name: String) -> void:
	_on_slot_clicked(slot_index, container_name)


func _on_slot_drag_started(slot_index: int, container_name: String) -> void:
	if _is_dragging():
		return
	var source_grid := _get_grid(container_name)
	if source_grid == null or slot_index < 0 or slot_index >= source_grid.get_child_count():
		return
	var data := _get_slot_data(container_name, slot_index)
	if data.is_empty():
		return
	var slot := source_grid.get_child(slot_index) as InventorySlot
	_drag_origin_index = slot_index
	_drag_origin_container = container_name
	_drag_source_quantity = int(data.get(&"quantity", 0))
	_drag_quantity = _drag_source_quantity
	slot.set_drag_origin(true)
	_create_drag_ghost(slot)
	_drag_pointer_position = _get_pointer_screen_position()


func _on_slot_drag_released(slot_index: int, container_name: String) -> void:
	if not _is_dragging():
		return
	if container_name == _drag_origin_container and slot_index == _drag_origin_index:
		_finish_drag(container_name, slot_index, _get_pointer_screen_position())
		return
	_finish_drag(container_name, slot_index, _get_pointer_screen_position())


func _finish_drag(target_container: String, target_slot_index: int, release_position: Vector2) -> void:
	_drag_pointer_position = release_position
	var origin_container := _drag_origin_container
	var origin_index := _drag_origin_index
	_cancel_drag_visual()
	if origin_index < 0 or origin_container.is_empty():
		_reset_drag_state()
		return
	var success := false
	if target_slot_index >= 0:
		if origin_container == target_container:
			if origin_container == "chest" and origin_index != target_slot_index:
				StorageManager.swap_slots(chest_id, origin_index, target_slot_index)
				success = true
			elif origin_container == "player" and origin_index != target_slot_index:
				InventoryManager.swap_slots(origin_index, target_slot_index)
				success = true
		elif origin_container == "player" and target_container == "chest":
			success = StorageManager.store_from_player(chest_id, origin_index, target_slot_index, _drag_quantity)
		elif origin_container == "chest" and target_container == "player":
			success = StorageManager.withdraw_to_player(chest_id, origin_index, target_slot_index, _drag_quantity)
	_reset_drag_state()
	if not success:
		_refresh_all()


func _create_drag_ghost(source_slot: InventorySlot) -> void:
	_drag_ghost = TextureRect.new()
	_drag_ghost.texture = source_slot.item_icon.texture
	_drag_ghost.modulate = source_slot.item_icon.modulate
	_drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 4096
	_drag_ghost.size = source_slot.get_global_rect().size
	_drag_ghost.global_position = _get_pointer_screen_position() - (_drag_ghost.size / 2.0)
	var quantity_badge := Label.new()
	quantity_badge.name = "QuantityBadge"
	quantity_badge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	quantity_badge.offset_left = 6.0
	quantity_badge.offset_top = -24.0
	quantity_badge.offset_right = -6.0
	quantity_badge.offset_bottom = -4.0
	quantity_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_badge.add_theme_font_size_override("font_size", 14)
	_drag_ghost.add_child(quantity_badge)
	add_child(_drag_ghost)
	_update_drag_ghost_quantity()


func _cancel_drag() -> void:
	_cancel_drag_visual()
	_reset_drag_state()
	_refresh_all()


func _cancel_drag_visual() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null


func _reset_drag_state() -> void:
	var source_grid := _get_grid(_drag_origin_container)
	if source_grid != null and _drag_origin_index >= 0 and _drag_origin_index < source_grid.get_child_count():
		(source_grid.get_child(_drag_origin_index) as InventorySlot).set_drag_origin(false)
	_drag_origin_index = -1
	_drag_origin_container = ""
	_drag_quantity = 0
	_drag_source_quantity = 0


func _is_dragging() -> bool:
	return _drag_origin_index != -1 and _drag_ghost != null


func _update_drag_ghost_quantity() -> void:
	if _drag_ghost == null:
		return
	var label := _drag_ghost.get_node_or_null("QuantityBadge") as Label
	if label != null:
		label.text = "x%d" % _drag_quantity


func _get_grid(container_name: String) -> GridContainer:
	match container_name:
		"player":
			return player_grid
		"chest":
			return chest_grid
		_:
			return null


func _get_slot_data(container_name: String, slot_index: int) -> Dictionary:
	if container_name == "player":
		return InventoryManager.get_slot_data(slot_index)
	if container_name == "chest":
		return StorageManager.get_slot_item(chest_id, slot_index)
	return {}


func _get_drop_target(global_position: Vector2) -> Dictionary:
	for container_name in ["player", "chest"]:
		var target_grid := _get_grid(container_name)
		if target_grid == null:
			continue
		for i in range(target_grid.get_child_count()):
			var slot := target_grid.get_child(i) as InventorySlot
			if slot.get_global_rect().has_point(global_position):
				return {&"container": container_name, &"slot_index": i}
	return {}


func _get_pointer_screen_position() -> Vector2:
	if MobileInputRouter != null and MobileInputRouter.has_touch_pointer():
		return MobileInputRouter.get_touch_pointer_screen_position()
	return get_viewport().get_mouse_position()


func _refresh_action_panel() -> void:
	var slot_data := _get_slot_data(_selected_container, _selected_slot_index)
	var has_selection := not _selected_container.is_empty() and not slot_data.is_empty()
	if not has_selection:
		selection_label.text = "No stack selected"
		move_to_chest_button.disabled = true
		move_to_pack_button.disabled = true
		transfer_all_button.disabled = true
		split_button.disabled = true
		action_hint_label.text = "Tap a stack to select it, drag to move it, or use the transfer buttons below."
		return
	var item_id := StringName(str(slot_data.get("id", slot_data.get("item_id", ""))))
	var quantity := int(slot_data.get("quantity", 0))
	var display_name := _get_item_name(item_id)
	selection_label.text = "%s x%d selected from %s" % [display_name, quantity, "pack" if _selected_container == "player" else "storage"]
	move_to_chest_button.disabled = _selected_container != "player" or _find_chest_target_slot(item_id) == -1
	move_to_pack_button.disabled = _selected_container != "chest" or _find_player_target_slot(item_id) == -1
	transfer_all_button.disabled = quantity <= 0
	split_button.disabled = quantity <= 1
	action_hint_label.text = "Use a visible transfer button or drag the stack to another slot."


func _on_move_to_chest_pressed() -> void:
	_transfer_selected(QuantityAction.PLAYER_TO_CHEST, false)


func _on_move_to_pack_pressed() -> void:
	_transfer_selected(QuantityAction.CHEST_TO_PLAYER, false)


func _on_transfer_all_pressed() -> void:
	if _selected_container == "player":
		_transfer_selected(QuantityAction.PLAYER_TO_CHEST, true)
	elif _selected_container == "chest":
		_transfer_selected(QuantityAction.CHEST_TO_PLAYER, true)


func _on_split_pressed() -> void:
	var slot_data := _get_slot_data(_selected_container, _selected_slot_index)
	var quantity := int(slot_data.get("quantity", 0))
	if quantity <= 1:
		return
	if _selected_container == "player":
		_open_quantity_modal(QuantityAction.PLAYER_TO_CHEST, quantity)
	elif _selected_container == "chest":
		_open_quantity_modal(QuantityAction.CHEST_TO_PLAYER, quantity)


func _transfer_selected(action: int, use_all: bool) -> void:
	var slot_data := _get_slot_data(_selected_container, _selected_slot_index)
	if slot_data.is_empty():
		return
	var item_id := StringName(str(slot_data.get("id", slot_data.get("item_id", ""))))
	var quantity := int(slot_data.get("quantity", 0))
	if item_id.is_empty() or quantity <= 0:
		return
	var move_quantity := quantity if use_all else 1
	var success := false
	match action:
		QuantityAction.PLAYER_TO_CHEST:
			var chest_slot := _find_chest_target_slot(item_id)
			if chest_slot != -1:
				success = StorageManager.store_from_player(chest_id, _selected_slot_index, chest_slot, move_quantity)
		QuantityAction.CHEST_TO_PLAYER:
			var player_slot := _find_player_target_slot(item_id)
			if player_slot != -1:
				success = StorageManager.withdraw_to_player(chest_id, _selected_slot_index, player_slot, move_quantity)
	if success:
		action_hint_label.text = "Transferred %s x%d." % [_get_item_name(item_id), move_quantity]
	else:
		action_hint_label.text = "No valid target slot for that transfer."
	_refresh_all()


func _find_chest_target_slot(item_id: StringName) -> int:
	for i in range(StorageManager.get_slot_count(chest_id)):
		var slot_data := StorageManager.get_slot_item(chest_id, i)
		if slot_data.is_empty() or StringName(str(slot_data.get("id", ""))) == item_id:
			return i
	return -1


func _find_player_target_slot(item_id: StringName) -> int:
	for i in range(InventoryManager.DEFAULT_SLOT_COUNT):
		var slot_data := InventoryManager.get_slot_data(i)
		if slot_data.item_id == &"" or StringName(String(slot_data.item_id)) == item_id:
			return i
	return -1


func _open_quantity_modal(action: int, max_quantity: int) -> void:
	_quantity_action = action
	_quantity_value = clampi(_quantity_value, 1, max_quantity)
	quantity_summary_label.text = "How many items should move?"
	quantity_confirm_button.text = "Transfer"
	_update_quantity_modal(max_quantity)
	quantity_modal.visible = true


func _update_quantity_modal(max_quantity: int) -> void:
	_quantity_value = clampi(_quantity_value, 1, max_quantity)
	quantity_value_label.text = "%d" % _quantity_value
	minus_button.disabled = _quantity_value <= 1
	plus_button.disabled = _quantity_value >= max_quantity


func _adjust_quantity(delta: int) -> void:
	if not quantity_modal.visible:
		return
	var slot_data := _get_slot_data(_selected_container, _selected_slot_index)
	var max_quantity := maxi(1, int(slot_data.get("quantity", 1)))
	_quantity_value += delta
	_update_quantity_modal(max_quantity)


func _close_quantity_modal() -> void:
	quantity_modal.visible = false
	_quantity_action = QuantityAction.NONE


func _confirm_quantity_modal() -> void:
	var action := _quantity_action
	_close_quantity_modal()
	var slot_data := _get_slot_data(_selected_container, _selected_slot_index)
	if slot_data.is_empty():
		return
	var original_quantity := int(slot_data.get("quantity", 0))
	if original_quantity <= 0:
		return
	match action:
		QuantityAction.PLAYER_TO_CHEST:
			var chest_slot := _find_chest_target_slot(StringName(String(slot_data.item_id)))
			if chest_slot != -1:
				StorageManager.store_from_player(chest_id, _selected_slot_index, chest_slot, _quantity_value)
		QuantityAction.CHEST_TO_PLAYER:
			var player_slot := _find_player_target_slot(StringName(str(slot_data.get("id", ""))))
			if player_slot != -1:
				StorageManager.withdraw_to_player(chest_id, _selected_slot_index, player_slot, _quantity_value)
	_refresh_all()


func _get_item_name(item_id: StringName) -> String:
	if item_id.is_empty():
		return "Unknown"
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", String(item_id)))
	return String(item_id).replace("_", " ").capitalize()
