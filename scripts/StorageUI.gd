extends CanvasLayer

signal ui_closed

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")
const DEFAULT_STORAGE_SLOT_COUNT := 20
const TOOLTIP_OFFSET := Vector2(18, 18)
const DRAG_HINT_TEXT := "Drag between player and chest. Wheel or Q/E adjusts qty."

@onready var panel: Panel = $StoragePanel
@onready var player_grid: GridContainer = $StoragePanel/PanelContent/PlayerColumn/PlayerGrid
@onready var chest_column: VBoxContainer = $StoragePanel/PanelContent/ChestColumn
@onready var chest_grid: GridContainer = $StoragePanel/PanelContent/ChestColumn/ChestGrid
@onready var player_weight_label: Label = $StoragePanel/PanelContent/PlayerColumn/WeightLabel
@onready var chest_title_label: Label = $StoragePanel/PanelContent/ChestColumn/ChestTitle
@onready var hint_label: Label = $StoragePanel/Footer/HintLabel

var chest_id: StringName = &""
var drag_origin_index := -1
var drag_origin_container := ""
var drag_quantity := 0
var drag_source_quantity := 0
var drag_ghost: TextureRect = null
var _storage_context: Dictionary = {}
var _storage_status_label: Label = null
var _storage_detail_label: Label = null


func _ready() -> void:
	layer = 11
	_ensure_grid_slot_count(player_grid, InventoryManager.DEFAULT_SLOT_COUNT, "player")
	_ensure_grid_slot_count(chest_grid, DEFAULT_STORAGE_SLOT_COUNT, "chest")
	_ensure_storage_info_labels()
	panel.visible = false
	InventoryManager.inventory_changed.connect(_refresh_all.unbind(1))
	InventoryManager.active_slot_changed.connect(_refresh_all.unbind(1))
	InventoryManager.weight_changed.connect(_on_weight_changed)
	StorageManager.chest_inventory_changed.connect(_on_chest_inventory_changed)
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)
	hint_label.text = DRAG_HINT_TEXT


func bind_chest(bound_chest_id: StringName) -> void:
	bind_storage(bound_chest_id, {})


func bind_storage(bound_chest_id: StringName, context: Dictionary = {}) -> void:
	chest_id = bound_chest_id
	_storage_context = context.duplicate(true)
	StorageManager.ensure_container(chest_id)
	var title := StorageManager.get_container_title(chest_id)
	if title == "Storage Chest":
		chest_title_label.text = "%s %s" % [title, String(chest_id).substr(0, 8)]
	else:
		chest_title_label.text = title
	_refresh_storage_info()
	_refresh_all()


func open_ui() -> void:
	panel.visible = true
	_refresh_storage_info()
	_refresh_all()


func close_ui() -> void:
	_cancel_drag()
	panel.visible = false
	ui_closed.emit()


func _input(event: InputEvent) -> void:
	if not panel.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.is_action_pressed("interact"):
			close_ui()
			get_viewport().set_input_as_handled()
			return

	if _is_dragging():
		if event is InputEventMouseButton and event.pressed:
			var mouse_event := event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_drag_quantity(1 if not mouse_event.shift_pressed else 5)
				get_viewport().set_input_as_handled()
				return
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_drag_quantity(-1 if not mouse_event.shift_pressed else -5)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventKey and event.pressed:
			var drag_key := event as InputEventKey
			if drag_key.keycode == KEY_UP or drag_key.keycode == KEY_E or drag_key.keycode == KEY_W:
				_adjust_drag_quantity(1 if not drag_key.shift_pressed else 5)
				get_viewport().set_input_as_handled()
				return
			if drag_key.keycode == KEY_DOWN or drag_key.keycode == KEY_Q or drag_key.keycode == KEY_S:
				_adjust_drag_quantity(-1 if not drag_key.shift_pressed else -5)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _is_dragging():
		var drop_target := _get_drop_target(get_viewport().get_mouse_position())
		_finish_drag(String(drop_target.get(&"container", "")), int(drop_target.get(&"slot_index", -1)))


func _process(_delta: float) -> void:
	if drag_ghost != null:
		drag_ghost.global_position = get_viewport().get_mouse_position() - (drag_ghost.size / 2.0)


func _build_grid(target_grid: GridContainer, container_name: String, start_index: int, count: int) -> void:
	for i in range(count):
		var slot = SLOT_SCENE.instantiate()
		target_grid.add_child(slot)
		slot.slot_index = start_index + i
		slot.custom_minimum_size = Vector2(64, 64)
		slot.drag_started.connect(_on_slot_drag_started.bind(container_name))
		slot.drag_released.connect(_on_slot_drag_released.bind(container_name))
		slot.clicked.connect(_on_slot_clicked.bind(container_name))


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
		var slot = target_grid.get_child(child_index)
		slot.slot_index = child_index


func _refresh_all(_unused = null) -> void:
	if chest_id.is_empty():
		return
	_ensure_grid_slot_count(chest_grid, StorageManager.get_slot_count(chest_id), "chest")
	_refresh_storage_info()
	_refresh_player_grid()
	_refresh_chest_grid()


func _refresh_player_grid() -> void:
	var active_index := InventoryManager.active_slot_index
	for i in range(player_grid.get_child_count()):
		var slot = player_grid.get_child(i)
		var data = InventoryManager.get_slot_data(i)
		slot.is_equipped = (i == active_index and data.item_id != &"")
		if data.item_id == &"":
			slot.clear()
		else:
			slot.update_slot(String(data.item_id), data.quantity, data.purity, null, null)


func _refresh_chest_grid() -> void:
	for i in range(chest_grid.get_child_count()):
		var slot = chest_grid.get_child(i)
		var data = StorageManager.get_slot_item(chest_id, i)
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


func _on_slot_drag_started(slot_index: int, container_name: String) -> void:
	if _is_dragging():
		return
	var source_grid := _get_grid(container_name)
	if source_grid == null or slot_index < 0 or slot_index >= source_grid.get_child_count():
		return
	var data := _get_slot_data(container_name, slot_index)
	if data.is_empty():
		return
	var slot = source_grid.get_child(slot_index)
	drag_origin_index = slot_index
	drag_origin_container = container_name
	drag_source_quantity = int(data.get(&"quantity", 0))
	drag_quantity = drag_source_quantity
	slot.set_drag_origin(true)
	_create_drag_ghost(slot)


func _on_slot_drag_released(slot_index: int, container_name: String) -> void:
	if not _is_dragging():
		return
	if container_name == drag_origin_container and slot_index == drag_origin_index:
		return
	_finish_drag(container_name, slot_index)


func _on_slot_clicked(slot_index: int, container_name: String) -> void:
	if container_name == "player":
		InventoryManager.set_active_slot(slot_index)


func _finish_drag(target_container: String, target_slot_index: int) -> void:
	var origin_container := drag_origin_container
	var origin_index := drag_origin_index
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
		elif origin_container == "player" and target_container == "chest":
			success = StorageManager.store_from_player(chest_id, origin_index, target_slot_index, drag_quantity)
		elif origin_container == "chest" and target_container == "player":
			success = StorageManager.withdraw_to_player(chest_id, origin_index, target_slot_index, drag_quantity)

	_reset_drag_state()
	if not success:
		_refresh_all()


func _cancel_drag() -> void:
	_cancel_drag_visual()
	_reset_drag_state()
	_refresh_all()


func _cancel_drag_visual() -> void:
	if drag_ghost != null:
		drag_ghost.queue_free()
		drag_ghost = null


func _reset_drag_state() -> void:
	var source_grid := _get_grid(drag_origin_container)
	if source_grid != null and drag_origin_index >= 0 and drag_origin_index < source_grid.get_child_count():
		source_grid.get_child(drag_origin_index).set_drag_origin(false)
	drag_origin_index = -1
	drag_origin_container = ""
	drag_quantity = 0
	drag_source_quantity = 0


func _create_drag_ghost(source_slot) -> void:
	drag_ghost = TextureRect.new()
	drag_ghost.texture = source_slot.item_icon.texture
	drag_ghost.modulate = source_slot.item_icon.modulate
	drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.z_index = 4096
	drag_ghost.size = source_slot.get_global_rect().size
	drag_ghost.global_position = get_viewport().get_mouse_position() - (drag_ghost.size / 2.0)
	var quantity_badge := Label.new()
	quantity_badge.name = "QuantityBadge"
	quantity_badge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	quantity_badge.offset_left = 6.0
	quantity_badge.offset_top = -24.0
	quantity_badge.offset_right = -6.0
	quantity_badge.offset_bottom = -4.0
	quantity_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_badge.add_theme_font_size_override("font_size", 14)
	drag_ghost.add_child(quantity_badge)
	add_child(drag_ghost)
	_update_drag_ghost_quantity()


func _adjust_drag_quantity(delta: int) -> void:
	if not _is_dragging() or drag_source_quantity <= 1:
		return
	drag_quantity = clampi(drag_quantity + delta, 1, drag_source_quantity)
	_update_drag_ghost_quantity()


func _update_drag_ghost_quantity() -> void:
	if drag_ghost == null:
		return
	var label := drag_ghost.get_node_or_null("QuantityBadge") as Label
	if label != null:
		label.text = "x%d" % drag_quantity


func _is_dragging() -> bool:
	return drag_origin_index != -1 and drag_ghost != null


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


func _get_drop_target(global_mouse_position: Vector2) -> Dictionary:
	for container_name in ["player", "chest"]:
		var target_grid := _get_grid(container_name)
		if target_grid == null:
			continue
		for i in range(target_grid.get_child_count()):
			var slot = target_grid.get_child(i)
			if slot.get_global_rect().has_point(global_mouse_position):
				return {&"container": container_name, &"slot_index": i}
	return {}
