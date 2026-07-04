extends Control

signal closed

const CONSUMER_PERIMETER_LIGHTS := &"perimeter_lights"
const CONSUMER_TRAP_NETWORK := &"trap_network"
const CONSUMER_FURNACE_BOOST := &"furnace_boost"
const CONSUMER_CHEM_BENCH_BOOST := &"chem_bench_boost"

@onready var lithium_color: ColorRect = $Panel/Margin/VBox/InputRow/LithiumSlot/ColorRect
@onready var iron_color: ColorRect = $Panel/Margin/VBox/InputRow/IronSlot/ColorRect
@onready var react_button: Button = $Panel/Margin/VBox/ReactButton
@onready var charge_bar: ProgressBar = $Panel/Margin/VBox/ChargeBar
@onready var charge_mins_label: Label = $Panel/Margin/VBox/ChargeMinsLabel
@onready var power_label: Label = $Panel/Margin/VBox/PowerLabel
@onready var power_slot_label: Label = $Panel/Margin/VBox/PowerSlot/Label
@onready var power_button: Button = $Panel/Margin/VBox/PowerSlot/Button
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var close_button: Button = $Panel/Margin/VBox/CloseButton
@onready var draw_label: Label = $Panel/Margin/VBox/Switchboard/DrawLabel
@onready var warning_label: Label = $Panel/Margin/VBox/Switchboard/WarningLabel
@onready var perimeter_toggle: CheckButton = $Panel/Margin/VBox/Switchboard/Consumers/PerimeterLights/Toggle
@onready var trap_toggle: CheckButton = $Panel/Margin/VBox/Switchboard/Consumers/TrapNetwork/Toggle
@onready var furnace_toggle: CheckButton = $Panel/Margin/VBox/Switchboard/Consumers/FurnaceBoost/Toggle
@onready var chem_toggle: CheckButton = $Panel/Margin/VBox/Switchboard/Consumers/ChemBenchBoost/Toggle
@onready var perimeter_draw: Label = $Panel/Margin/VBox/Switchboard/Consumers/PerimeterLights/Draw
@onready var trap_draw: Label = $Panel/Margin/VBox/Switchboard/Consumers/TrapNetwork/Draw
@onready var furnace_draw: Label = $Panel/Margin/VBox/Switchboard/Consumers/FurnaceBoost/Draw
@onready var chem_draw: Label = $Panel/Margin/VBox/Switchboard/Consumers/ChemBenchBoost/Draw

var _is_open := false
var _base_grid: Node = null
var _power_switchboard: Node = null
var _refreshing_toggles := false


func _ready() -> void:
	visible = false
	_bind_power_services()
	title_label.text = "Battery Station"
	power_label.text = "DEFENSE GRID POWER"
	power_slot_label.text = "Defense Charge Slot"
	power_button.text = "Insert Energy Cell (+20 min)"
	react_button.pressed.connect(_on_react_pressed)
	power_button.pressed.connect(_on_power_pressed)
	close_button.pressed.connect(close)
	perimeter_toggle.toggled.connect(_on_perimeter_toggled)
	trap_toggle.toggled.connect(_on_trap_toggled)
	furnace_toggle.toggled.connect(_on_furnace_toggled)
	chem_toggle.toggled.connect(_on_chem_toggled)
	if InventoryManager != null and InventoryManager.has_signal("inventory_changed"):
		InventoryManager.inventory_changed.connect(_on_inventory_changed)
	if not EventBus.service_registered.is_connected(_on_service_registered):
		EventBus.service_registered.connect(_on_service_registered)


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
	var has_li := InventoryManager.has_item(&"lithium", 1)
	var has_fe := InventoryManager.has_item(&"iron", 1)
	var has_cell := InventoryManager.has_item(&"energy_cell", 1)

	lithium_color.color = Color(0.1, 0.5, 0.1, 1.0) if has_li else Color(0.5, 0.1, 0.1, 1.0)
	iron_color.color = Color(0.1, 0.5, 0.1, 1.0) if has_fe else Color(0.5, 0.1, 0.1, 1.0)
	react_button.disabled = not (has_li and has_fe)

	var grid_current := 0.0
	var grid_maximum := 0.0
	if _base_grid != null:
		grid_current = float(_base_grid.get("charge_level"))
		grid_maximum = float(_base_grid.get("MAX_CHARGE"))
		_update_charge_display(grid_current, grid_maximum)
	power_button.disabled = not has_cell or (grid_maximum > 0.0 and grid_current >= grid_maximum)

	_refresh_switchboard_panel()


func _refresh_switchboard_panel() -> void:
	if _power_switchboard == null:
		return

	_refreshing_toggles = true
	perimeter_toggle.button_pressed = _power_switchboard.is_consumer_enabled(CONSUMER_PERIMETER_LIGHTS)
	trap_toggle.button_pressed = _power_switchboard.is_consumer_enabled(CONSUMER_TRAP_NETWORK)
	furnace_toggle.button_pressed = _power_switchboard.is_consumer_enabled(CONSUMER_FURNACE_BOOST)
	chem_toggle.button_pressed = _power_switchboard.is_consumer_enabled(CONSUMER_CHEM_BENCH_BOOST)
	_refreshing_toggles = false

	perimeter_draw.text = _format_draw(_power_switchboard.get_consumer_draw_units_per_minute(CONSUMER_PERIMETER_LIGHTS))
	trap_draw.text = _format_draw(_power_switchboard.get_consumer_draw_units_per_minute(CONSUMER_TRAP_NETWORK))
	furnace_draw.text = _format_draw(_power_switchboard.get_consumer_draw_units_per_minute(CONSUMER_FURNACE_BOOST))
	chem_draw.text = _format_draw(_power_switchboard.get_consumer_draw_units_per_minute(CONSUMER_CHEM_BENCH_BOOST))

	var total_draw := float(_power_switchboard.get_total_draw_units_per_minute())
	var capacity := float(_power_switchboard.get_total_capacity_units_per_minute())
	draw_label.text = "Current Draw %.2f / %.2f units/min" % [total_draw, capacity]
	if total_draw > capacity:
		warning_label.visible = true
		warning_label.text = "Warning: active draw exceeds switchboard capacity."
	else:
		warning_label.visible = false
		warning_label.text = ""


func _on_charge_changed(current: float, maximum: float) -> void:
	if _is_open:
		_update_charge_display(current, maximum)
		_refresh_switchboard_panel()


func _on_inventory_changed(_slot_index: int = -1) -> void:
	if _is_open:
		_refresh_ui()


func _on_switchboard_changed() -> void:
	if _is_open:
		_refresh_switchboard_panel()


func _update_charge_display(current: float, maximum: float) -> void:
	if maximum <= 0.0:
		return
	charge_bar.value = (current / maximum) * 100.0
	var mins := int(current)
	var secs := int((current - float(mins)) * 60.0)
	charge_mins_label.text = "%d:%02d / 30:00 remaining" % [mins, secs]

	var pct := current / maximum
	if pct > 0.5:
		charge_bar.modulate = Color(0.3 + (1.0 - pct) * 1.4, 1.0, 0.3, 1.0)
	elif pct > 0.2:
		charge_bar.modulate = Color(1.0, pct * 2.0, 0.2, 1.0)
	else:
		charge_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)


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
	if float(_base_grid.get("charge_level")) >= float(_base_grid.get("MAX_CHARGE")):
		return
	InventoryManager.remove_item(&"energy_cell", 1)
	if _base_grid.has_method("add_charge_cell"):
		_base_grid.add_charge_cell()
	else:
		_base_grid.add_charge(20.0)
	if GameManager != null and GameManager.has_method("unlock_advanced_scanner"):
		GameManager.unlock_advanced_scanner()
	_refresh_ui()


func _on_perimeter_toggled(enabled: bool) -> void:
	_set_consumer(CONSUMER_PERIMETER_LIGHTS, enabled)


func _on_trap_toggled(enabled: bool) -> void:
	_set_consumer(CONSUMER_TRAP_NETWORK, enabled)


func _on_furnace_toggled(enabled: bool) -> void:
	_set_consumer(CONSUMER_FURNACE_BOOST, enabled)


func _on_chem_toggled(enabled: bool) -> void:
	_set_consumer(CONSUMER_CHEM_BENCH_BOOST, enabled)


func _set_consumer(consumer_id: StringName, enabled: bool) -> void:
	if _refreshing_toggles or _power_switchboard == null:
		return
	_power_switchboard.set_consumer_enabled(consumer_id, enabled)
	_refresh_switchboard_panel()


func _format_draw(draw_units_per_minute: float) -> String:
	return "%.2f /min" % draw_units_per_minute


func _on_service_registered(service_id: StringName, _service: Node) -> void:
	if service_id == EventBus.SERVICE_BASE_GRID or service_id == EventBus.SERVICE_POWER_SWITCHBOARD:
		_bind_power_services()
		if _is_open:
			_refresh_ui()


func _bind_power_services() -> void:
	var next_base_grid := EventBus.get_base_grid()
	if next_base_grid != null and next_base_grid != _base_grid:
		_base_grid = next_base_grid
		if _base_grid.has_signal("charge_level_changed") and not _base_grid.charge_level_changed.is_connected(_on_charge_changed):
			_base_grid.charge_level_changed.connect(_on_charge_changed)

	_power_switchboard = EventBus.get_power_switchboard()
	if _power_switchboard != null and _power_switchboard.has_signal("switchboard_changed"):
		if not _power_switchboard.switchboard_changed.is_connected(_on_switchboard_changed):
			_power_switchboard.switchboard_changed.connect(_on_switchboard_changed)
