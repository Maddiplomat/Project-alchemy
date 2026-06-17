extends PointLight2D

var _base_grid: Node = null
var _registered_with_defense := false

@export var defense_radius := 96.0
@export var drain_units_per_minute := 1.0
@export var active_energy := 0.8
@export var light_color := Color(0.70, 0.92, 1.0, 0.92)
@export var light_color_inner := Color(0.42, 0.82, 1.0, 0.52)


func _ready() -> void:
	add_to_group(&"powered_light")
	_base_grid = get_node_or_null("/root/BaseGrid")
	if _base_grid == null:
		energy = 0.0
		return

	_configure_light_texture()
	if _base_grid.has_signal("power_activated"):
		_base_grid.power_activated.connect(_on_power_activated)
	if _base_grid.has_signal("power_deactivated"):
		_base_grid.power_deactivated.connect(_on_power_deactivated)
	if GameManager != null:
		if GameManager.has_signal("night_started"):
			GameManager.night_started.connect(_refresh_power_state)
		if GameManager.has_signal("day_started"):
			GameManager.day_started.connect(_refresh_power_state)
	if PowerSwitchboard != null and PowerSwitchboard.has_signal("switchboard_changed"):
		PowerSwitchboard.switchboard_changed.connect(_refresh_power_state)
	_refresh_power_state()


func get_power_drain_units_per_minute() -> float:
	if PowerSwitchboard != null and PowerSwitchboard.has_method("is_consumer_enabled"):
		if not PowerSwitchboard.is_consumer_enabled(PowerSwitchboard.CONSUMER_PERIMETER_LIGHTS):
			return 0.0
	return drain_units_per_minute


func _exit_tree() -> void:
	_unregister_with_defense()


func _on_power_activated() -> void:
	_refresh_power_state()


func _on_power_deactivated() -> void:
	_refresh_power_state()


func _refresh_power_state() -> void:
	var should_show_light := _should_show_visual_light()
	var should_enable_defense := _should_enable_defense_effect()
	energy = active_energy if should_show_light else 0.0
	if should_enable_defense:
		_register_with_defense()
	else:
		_unregister_with_defense()


func _should_show_visual_light() -> bool:
	if _base_grid == null or not _base_grid.has_method("is_powered") or not _base_grid.is_powered():
		return false
	if PowerSwitchboard != null and PowerSwitchboard.has_method("is_consumer_enabled"):
		if not PowerSwitchboard.is_consumer_enabled(PowerSwitchboard.CONSUMER_PERIMETER_LIGHTS):
			return false
	return _is_defense_light_source()


func _should_enable_defense_effect() -> bool:
	if not _should_show_visual_light():
		return false
	if GameManager == null or not GameManager.has_method("is_night") or not GameManager.is_night():
		return false
	return true


func _is_defense_light_source() -> bool:
	return is_in_group(&"placed_stations") or get_parent() == null or get_parent().is_in_group(&"placed_stations") or get_parent().name == "BatteryStation"


func _register_with_defense() -> void:
	if _registered_with_defense or BaseDefenseSystem == null or not BaseDefenseSystem.has_method("register_light"):
		return
	BaseDefenseSystem.register_light(self, defense_radius, drain_units_per_minute)
	_registered_with_defense = true


func _unregister_with_defense() -> void:
	if not _registered_with_defense or BaseDefenseSystem == null or not BaseDefenseSystem.has_method("unregister_light"):
		return
	BaseDefenseSystem.unregister_light(self)
	_registered_with_defense = false


func _configure_light_texture() -> void:
	var gradient := Gradient.new()
	gradient.add_point(0.0, light_color)
	gradient.add_point(0.35, light_color_inner)
	gradient.add_point(1.0, Color(0.0, 0.0, 0.0, 0.0))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.width = 256
	gradient_texture.height = 256
	gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	gradient_texture.gradient = gradient
	texture = gradient_texture
	offset = Vector2(0.0, -8.0)
