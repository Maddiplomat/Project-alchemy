extends CanvasLayer

@onready var panel = $InventoryPanel
@onready var grid = $InventoryPanel/Grid

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")
const SLOT_COUNT := 20

var drag_origin_index := -1
var drag_ghost: TextureRect = null

func _ready():
	for i in range(SLOT_COUNT):
		var slot = SLOT_SCENE.instantiate()
		grid.add_child(slot)
		slot.slot_index = i
		slot.drag_started.connect(_on_slot_drag_started)
		slot.drag_released.connect(_on_slot_drag_released)
		
		# Set minimum size for GridContainer to respect
		slot.custom_minimum_size = Vector2(64, 64)
		
		# Set ItemIcon anchors and modes
		var icon = slot.get_node("ItemIcon")
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Set QuantityLabel anchors
		var label = slot.get_node("QuantityLabel")
		label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		
	InventoryManager.inventory_changed.connect(refresh_grid)
	refresh_grid()
	
	call_deferred("_setup_panel")

func _setup_panel():
	var vp_size = get_viewport().get_visible_rect().size
	panel.position = Vector2(vp_size.x, (vp_size.y - panel.size.y) / 2)
	panel.visible = false

func _input(event):
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed and not event.echo:
		toggle_inventory()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _is_dragging():
			_finish_drag(_get_slot_index_at_position(get_viewport().get_mouse_position()))

func _process(_delta: float) -> void:
	if drag_ghost != null:
		drag_ghost.global_position = get_viewport().get_mouse_position() - (drag_ghost.size / 2.0)

func toggle_inventory():
	var vp_size = get_viewport().get_visible_rect().size
	var target_x = vp_size.x
	
	if not panel.visible or panel.position.x >= vp_size.x - 1:
		# opening
		panel.visible = true
		target_x = vp_size.x - panel.size.x - 50
		refresh_grid()
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", target_x, 0.4)
	
	if target_x >= vp_size.x - 1:
		# closing
		tween.tween_callback(func(): panel.visible = false)

func refresh_grid():
	for i in range(grid.get_child_count()):
		var slot = grid.get_child(i)
		var data = InventoryManager.get_slot_item(i)
		if not data.is_empty():
			slot.update_slot(data.id, data.quantity, data.purity)
		else:
			slot.clear()

func _on_slot_drag_started(slot_index: int) -> void:
	if _is_dragging():
		return
	if slot_index < 0 or slot_index >= grid.get_child_count():
		return
	
	var slot = grid.get_child(slot_index)
	if not slot.has_item():
		return
	
	drag_origin_index = slot_index
	slot.set_drag_origin(true)
	_create_drag_ghost(slot)

func _on_slot_drag_released(slot_index: int) -> void:
	if _is_dragging():
		_finish_drag(slot_index)

func _create_drag_ghost(source_slot) -> void:
	_clear_drag_ghost()
	
	drag_ghost = TextureRect.new()
	drag_ghost.texture = source_slot.item_icon.texture
	drag_ghost.modulate = source_slot.item_icon.modulate
	drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.z_index = 4096
	drag_ghost.size = source_slot.get_global_rect().size
	drag_ghost.global_position = get_viewport().get_mouse_position() - (drag_ghost.size / 2.0)
	add_child(drag_ghost)

func _finish_drag(drop_slot_index: int) -> void:
	var from_slot := drag_origin_index
	_clear_drag_ghost()
	drag_origin_index = -1
	
	if from_slot >= 0 and from_slot < grid.get_child_count():
		grid.get_child(from_slot).set_drag_origin(false)
	
	if drop_slot_index >= 0 and drop_slot_index < grid.get_child_count() and drop_slot_index != from_slot:
		InventoryManager.swap_slots(from_slot, drop_slot_index)

func _get_slot_index_at_position(global_mouse_position: Vector2) -> int:
	for i in range(grid.get_child_count()):
		var slot = grid.get_child(i)
		if slot.get_global_rect().has_point(global_mouse_position):
			return i
	
	return -1

func _clear_drag_ghost() -> void:
	if drag_ghost != null:
		drag_ghost.queue_free()
		drag_ghost = null

func _is_dragging() -> bool:
	return drag_origin_index != -1 and drag_ghost != null
