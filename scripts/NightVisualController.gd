extends Node

@export var night_modulate_path: NodePath
@export var frost_overlay_path: NodePath

var _night_modulate: CanvasModulate = null
var _frost_rect: TextureRect = null
var _cold_system: Node = null


func _ready() -> void:
	EventBus.register_service(EventBus.SERVICE_NIGHT_VISUAL_CONTROLLER, self)
	_night_modulate = get_node_or_null(night_modulate_path) as CanvasModulate
	_frost_rect = get_node_or_null(frost_overlay_path) as TextureRect
	_bind_cold_system(EventBus.get_cold_system())
	if not EventBus.service_registered.is_connected(_on_service_registered):
		EventBus.service_registered.connect(_on_service_registered)
	if GameManager != null and GameManager.has_signal("time_of_day_changed"):
		GameManager.time_of_day_changed.connect(_update_night_modulate)
	if not get_viewport().size_changed.is_connected(_refresh_frost_texture):
		get_viewport().size_changed.connect(_refresh_frost_texture)
	if _frost_rect != null:
		_frost_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frost_rect.modulate.a = 0.0
		_refresh_frost_texture()
	_update_night_modulate()


func _exit_tree() -> void:
	EventBus.unregister_service(EventBus.SERVICE_NIGHT_VISUAL_CONTROLLER, self)


func _on_service_registered(service_id: StringName, service: Node) -> void:
	if service_id == EventBus.SERVICE_COLD_SYSTEM:
		_bind_cold_system(service)


func _bind_cold_system(service: Node) -> void:
	if service == null or service == _cold_system:
		return
	_cold_system = service
	if _cold_system.has_signal("cold_level_changed"):
		if not _cold_system.cold_level_changed.is_connected(_on_cold_level_changed):
			_cold_system.cold_level_changed.connect(_on_cold_level_changed)
	_on_cold_level_changed(float(_cold_system.get("cold_level")), float(_cold_system.get("COLD_MAX")))


func _update_night_modulate(_time_of_day: float = 0.0) -> void:
	if _night_modulate == null or GameManager == null:
		return
	if GameManager.is_night():
		_night_modulate.color = Color(0.6, 0.6, 0.7, 1.0)
	else:
		_night_modulate.color = Color(1.0, 1.0, 1.0, 1.0)


func _on_cold_level_changed(current: float, maximum: float) -> void:
	if _frost_rect == null or maximum <= 0.0:
		return
	_frost_rect.modulate.a = (current / maximum) * 0.95


func _refresh_frost_texture() -> void:
	if _frost_rect == null:
		return
	_frost_rect.texture = _build_frost_texture()


func _build_frost_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.8, 0.9, 1.0, 0.0))
	gradient.add_point(0.7, Color(0.8, 0.9, 1.0, 0.1))
	gradient.add_point(1.0, Color(0.6, 0.8, 1.0, 0.6))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	var viewport_size := get_viewport().get_visible_rect().size
	texture.width = maxi(int(viewport_size.x), 1)
	texture.height = maxi(int(viewport_size.y), 1)
	return texture
