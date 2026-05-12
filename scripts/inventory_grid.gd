extends Control
class_name InventoryGrid

const CRAFT_READY_COLOR = Color(0.2, 0.8, 0.4, 0.8)

@export var crafting_highlight: Panel
var _highlight_tween: Tween

@onready var grid_container: GridContainer = $GridContainer
@onready var capacity_progress: ProgressBar = $VBoxContainer/CapacityBar
@onready var weight_label: Label = $VBoxContainer/CapacityLabel
@onready var title_label: Label = $VBoxContainer/TitleLabel

const InventorySlotClass = preload("res://scripts/inventory_slot.gd")

var _slots: Array[InventorySlotClass] = []


func _ready() -> void:
	if grid_container == null:
		push_error("InventoryGrid: GridContainer not found")
		return
	if capacity_progress == null:
		push_error("InventoryGrid: CapacityBar not found")
		return
	if weight_label == null:
		push_error("InventoryGrid: CapacityLabel not found")
		return

	for child in grid_container.get_children():
		if child is InventorySlotClass:
			_slots.append(child)

	if _slots.size() != InventoryManager.MAX_SLOTS:
		push_error("InventoryGrid: Slot count mismatch. Expected %d, found %d." % [InventoryManager.MAX_SLOTS, _slots.size()])

	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	InventoryManager.active_slot_changed.connect(_on_active_slot_changed)
	InventoryManager.weight_changed.connect(_on_weight_changed)
	InventoryManager.purity_changed.connect(_on_purity_changed)

	_update_all_slots()
	_update_active_slot(InventoryManager.active_slot_index)
	_update_weight_display(InventoryManager.total_weight, InventoryManager.carry_capacity)

func _process(_delta: float) -> void:
	if CraftingManager.get_craftable_recipe() != null:
		_start_highlight()
	else:
		_stop_highlight()


func _on_inventory_changed(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _slots.size():
		var slot_data := InventoryManager.get_slot_data(slot_index)
		var ui_slot := _slots[slot_index]
		
		ui_slot.item_id = slot_data["item_id"]
		ui_slot.quantity = slot_data["quantity"]
		ui_slot.purity = slot_data["purity"]
		
		if ui_slot.item_id.is_empty():
			ui_slot.item_color = Color.TRANSPARENT
		else:
			ui_slot.item_color = _get_item_color(ui_slot.item_id)
		
		ui_slot.update_display()


func _on_active_slot_changed(new_index: int) -> void:
	_update_active_slot(new_index)


func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	_update_weight_display(total_weight, carry_capacity)


func _on_purity_changed(slot_index: int, new_purity: float) -> void:
	if slot_index >= 0 and slot_index < _slots.size():
		_slots[slot_index].purity = new_purity
		_slots[slot_index].update_display()


func _update_all_slots() -> void:
	for i in range(_slots.size()):
		_on_inventory_changed(i)


func _update_active_slot(active_index: int) -> void:
	for i in range(_slots.size()):
		_slots[i].is_active = (i == active_index)
		_slots[i].update_display()


func _update_weight_display(total_weight: float, carry_capacity: float) -> void:
	var safe_capacity := maxf(carry_capacity, 0.0)
	var displayed_weight := minf(total_weight, safe_capacity) if safe_capacity > 0.0 else 0.0
	var weight_ratio := total_weight / safe_capacity if safe_capacity > 0.0 else 0.0
	
	capacity_progress.max_value = safe_capacity
	capacity_progress.value = displayed_weight
	weight_label.text = "%.1f / %.1f kg" % [total_weight, safe_capacity]
	
	if weight_ratio > 1.0:
		capacity_progress.modulate = Color.RED
		weight_label.modulate = Color.RED
	elif weight_ratio > 0.8:
		capacity_progress.modulate = Color.ORANGE
		weight_label.modulate = Color.ORANGE
	else:
		capacity_progress.modulate = Color.WHITE
		weight_label.modulate = Color.WHITE


func _start_highlight() -> void:
	if _highlight_tween != null:
		return
	
	crafting_highlight.visible = true
	var style = StyleBoxFlat.new()
	style.draw_center = false
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.border_color = CRAFT_READY_COLOR
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	crafting_highlight.add_theme_stylebox_override("panel", style)
	
	_highlight_tween = create_tween().set_loops()
	_highlight_tween.tween_property(crafting_highlight, "modulate:a", 1.0, 0.6).from(0.2)
	_highlight_tween.tween_property(crafting_highlight, "modulate:a", 0.2, 0.6)


func _stop_highlight() -> void:
	if _highlight_tween != null:
		_highlight_tween.kill()
		_highlight_tween = null
	crafting_highlight.visible = false

func _get_item_color(item_id: String) -> Color:
	match item_id:
		"wood":
			return Color.BURLYWOOD
		"stone":
			return Color.GRAY
		"iron":
			return Color.SILVER
		_:
			return Color.WHITE
