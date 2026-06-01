extends Control

signal closed

# Slot nodes
@onready var lithium_color: ColorRect = $Panel/VBoxContainer/InputContainer/LithiumSlot/ColorRect
@onready var iron_color: ColorRect = $Panel/VBoxContainer/InputContainer/IronSlot/ColorRect
@onready var react_button: Button = $Panel/VBoxContainer/ReactButton
@onready var charge_bar: ProgressBar = $Panel/VBoxContainer/ChargeBar
@onready var charge_mins_label: Label = $Panel/VBoxContainer/ChargeMinsLabel
@onready var power_button: Button = $Panel/VBoxContainer/PowerSlot/Button
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var _is_open := false
var _base_grid: Node = null


func _ready() -> void:
	visible = false
	_base_grid = get_node_or_null("/root/BaseGrid")
	react_button.pressed.connect(_on_react_pressed)
	power_button.pressed.connect(_on_power_pressed)
	close_button.pressed.connect(close)
	if _base_grid and _base_grid.has_signal("charge_level_changed"):
		_base_grid.charge_level_changed.connect(_on_charge_changed)


func _process(_delta: float) -> void:
	if not _is_open:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		close()


func open() -> void:
	_is_open = true
	visible = true
	_refresh_ui()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	closed.emit()


func _refresh_ui() -> void:
	var has_li: bool = InventoryManager.has_item(&"lithium", 1)
	var has_fe: bool = InventoryManager.has_item(&"iron", 1)
	var has_cell: bool = InventoryManager.has_item(&"energy_cell", 1)

	# Input slot colours — green if available, red if not
	lithium_color.color = Color(0.1, 0.5, 0.1, 1) if has_li else Color(0.5, 0.1, 0.1, 1)
	iron_color.color   = Color(0.1, 0.5, 0.1, 1) if has_fe else Color(0.5, 0.1, 0.1, 1)

	react_button.disabled = not (has_li and has_fe)
	power_button.disabled = not has_cell

	if _base_grid:
		_update_charge_display(
			float(_base_grid.get("charge_level")),
			float(_base_grid.get("MAX_CHARGE"))
		)


func _on_charge_changed(current: float, maximum: float) -> void:
	if _is_open:
		_update_charge_display(current, maximum)


func _update_charge_display(current: float, maximum: float) -> void:
	if maximum <= 0.0:
		return
	charge_bar.value = (current / maximum) * 100.0
	var mins := int(current)
	var secs := int((current - float(mins)) * 60.0)
	charge_mins_label.text = "%d:%02d / 60:00 remaining" % [mins, secs]

	# Colour the bar green → yellow → red
	var pct := current / maximum
	if pct > 0.5:
		charge_bar.modulate = Color(0.3 + (1.0 - pct) * 1.4, 1.0, 0.3, 1)
	elif pct > 0.2:
		charge_bar.modulate = Color(1.0, pct * 2.0, 0.2, 1)
	else:
		charge_bar.modulate = Color(1.0, 0.2, 0.2, 1)


func _on_react_pressed() -> void:
	if not (InventoryManager.has_item(&"lithium", 1) and InventoryManager.has_item(&"iron", 1)):
		return
	InventoryManager.remove_item(&"lithium", 1)
	InventoryManager.remove_item(&"iron", 1)
	InventoryManager.add_item({
		&"id": &"energy_cell",
		&"display_name": "Energy Cell",
		&"category": InventoryManager.InventoryItemCategory.CRAFTED
	}, 2)
	_refresh_ui()


func _on_power_pressed() -> void:
	if not InventoryManager.has_item(&"energy_cell", 1):
		return
	if _base_grid == null:
		return
	InventoryManager.remove_item(&"energy_cell", 1)
	# Each Energy Cell refills the grid to full (60 minutes)
	_base_grid.add_charge(float(_base_grid.get("MAX_CHARGE")))
	_refresh_ui()
