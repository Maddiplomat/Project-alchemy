extends PointLight2D

static var _cached_textures: Dictionary = {}

var _base_grid: Node = null
var _power_switchboard: Node = null
var _registered_with_defense := false
var _disrupted_until_msec := 0

@export var defense_radius := 96.0
@export var drain_units_per_minute := 1.0
@export var active_energy := 0.8
@export var light_color := Color(0.70, 0.92, 1.0, 0.92)
@export var light_color_inner := Color(0.42, 0.82, 1.0, 0.52)


func _ready() -> void:
	add_to_group(&"powered_light")
	_bind_power_services()
	if _base_grid == null:
		energy = 0.0
	set_process(false)

	_configure_light_texture()
	if GameManager != null:
		if GameManager.has_signal("night_started"):
			GameManager.night_started.connect(_refresh_power_state)
		if GameManager.has_signal("day_started"):
			GameManager.day_started.connect(_refresh_power_state)
	if not EventBus.service_registered.is_connected(_on_service_registered):
		EventBus.service_registered.connect(_on_service_registered)
	_refresh_power_state()


func _process(_delta: float) -> void:
	if _disrupted_until_msec <= 0:
		return
	if Time.get_ticks_msec() < _disrupted_until_msec:
		return
	_disrupted_until_msec = 0
	_refresh_power_state()


func get_power_drain_units_per_minute() -> float:
	if _is_disrupted():
		return 0.0
	if _power_switchboard != null and _power_switchboard.has_method("is_consumer_enabled"):
		if not _power_switchboard.is_consumer_enabled(&"perimeter_lights"):
			return 0.0
	return drain_units_per_minute


func disrupt(duration_seconds: float) -> void:
	_disrupted_until_msec = maxi(
		_disrupted_until_msec,
		Time.get_ticks_msec() + int(maxf(duration_seconds, 0.0) * 1000.0)
	)
	set_process(true)
	_refresh_power_state()


func is_attracting_swarmer() -> bool:
	return _should_show_visual_light()


func _exit_tree() -> void:
	_unregister_with_defense()


func _on_power_activated() -> void:
	_refresh_power_state()


func _on_power_deactivated() -> void:
	_refresh_power_state()


func _refresh_power_state() -> void:
	var should_show_light := _should_show_visual_light()
	var should_enable_defense := _should_enable_defense_effect()
	var energy_scale := 1.0
	if MobilePerformance != null and MobilePerformance.has_method("get_light_energy_scale"):
		energy_scale = float(MobilePerformance.get_light_energy_scale())
	energy = active_energy * energy_scale if should_show_light else 0.0
	if should_enable_defense:
		_register_with_defense()
	else:
		_unregister_with_defense()
	set_process(_is_disrupted())


func _should_show_visual_light() -> bool:
	if _is_disrupted():
		return false
	if _base_grid == null or not _base_grid.has_method("is_powered") or not _base_grid.is_powered():
		return false
	if _power_switchboard != null and _power_switchboard.has_method("is_consumer_enabled"):
		if not _power_switchboard.is_consumer_enabled(&"perimeter_lights"):
			return false
	return _is_defense_light_source()


func _is_disrupted() -> bool:
	return Time.get_ticks_msec() < _disrupted_until_msec


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
	var texture_size := 128
	if MobilePerformance != null and MobilePerformance.has_method("get_light_texture_size"):
		texture_size = int(MobilePerformance.get_light_texture_size())
	var cache_key := "%d|%s|%s" % [texture_size, str(light_color), str(light_color_inner)]
	if not _cached_textures.has(cache_key):
		var gradient := Gradient.new()
		gradient.add_point(0.0, light_color)
		gradient.add_point(0.35, light_color_inner)
		gradient.add_point(1.0, Color(0.0, 0.0, 0.0, 0.0))
		var gradient_texture := GradientTexture2D.new()
		gradient_texture.width = texture_size
		gradient_texture.height = texture_size
		gradient_texture.fill = GradientTexture2D.FILL_RADIAL
		gradient_texture.gradient = gradient
		_cached_textures[cache_key] = gradient_texture
	texture = _cached_textures[cache_key]
	offset = Vector2(0.0, -8.0)


func _on_service_registered(service_id: StringName, _service: Node) -> void:
	if service_id == EventBus.SERVICE_BASE_GRID or service_id == EventBus.SERVICE_POWER_SWITCHBOARD:
		_bind_power_services()
		_refresh_power_state()


func _bind_power_services() -> void:
	var next_base_grid := EventBus.get_base_grid()
	if next_base_grid != null and next_base_grid != _base_grid:
		_base_grid = next_base_grid
		if _base_grid.has_signal("power_activated") and not _base_grid.power_activated.is_connected(_on_power_activated):
			_base_grid.power_activated.connect(_on_power_activated)
		if _base_grid.has_signal("power_deactivated") and not _base_grid.power_deactivated.is_connected(_on_power_deactivated):
			_base_grid.power_deactivated.connect(_on_power_deactivated)

	_power_switchboard = EventBus.get_power_switchboard()
	if _power_switchboard != null and _power_switchboard.has_signal("switchboard_changed"):
		if not _power_switchboard.switchboard_changed.is_connected(_refresh_power_state):
			_power_switchboard.switchboard_changed.connect(_refresh_power_state)
