extends Control

const BACKGROUND_COLOR := Color(0.07, 0.11, 0.09, 0.82)
const BORDER_COLOR := Color(0.72, 0.82, 0.76, 0.40)
const PLAYER_COLOR := Color(0.96, 0.95, 0.86, 1.0)
const MARKER_COLORS := {
	&"home": Color(0.46, 0.88, 0.58, 1.0),
	&"mine": Color(0.82, 0.72, 0.48, 1.0),
	&"sulfur_flats": Color(0.95, 0.86, 0.28, 1.0),
	&"death": Color(0.92, 0.30, 0.28, 1.0),
}

var _map_markers: Node = null


func _ready() -> void:
	_bind_map_markers(EventBus.get_map_markers())
	if not EventBus.service_registered.is_connected(_on_service_registered):
		EventBus.service_registered.connect(_on_service_registered)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)

	if _map_markers == null:
		return

	var world_rect := _map_markers.get_world_rect() as Rect2
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return

	for marker: Dictionary in _map_markers.get_markers():
		var marker_type: StringName = StringName(marker.get(&"type", &""))
		var marker_position: Vector2 = marker.get(&"world_position", Vector2.ZERO) as Vector2
		var point: Vector2 = _world_to_minimap(marker_position, world_rect)
		var color: Color = MARKER_COLORS.get(marker_type, Color.WHITE)
		draw_circle(point, 3.0, color)

	var player_position: Vector2 = _map_markers.get_player_world_position()
	if player_position != Vector2.ZERO:
		var player_point: Vector2 = _world_to_minimap(player_position, world_rect)
		draw_circle(player_point, 4.0, PLAYER_COLOR)
		draw_line(player_point + Vector2(-3.0, 0.0), player_point + Vector2(3.0, 0.0), Color.BLACK, 1.0)
		draw_line(player_point + Vector2(0.0, -3.0), player_point + Vector2(0.0, 3.0), Color.BLACK, 1.0)


func _world_to_minimap(world_position: Vector2, world_rect: Rect2) -> Vector2:
	var normalized_x: float = inverse_lerp(world_rect.position.x, world_rect.end.x, world_position.x)
	var normalized_y: float = inverse_lerp(world_rect.position.y, world_rect.end.y, world_position.y)
	return Vector2(
		clampf(normalized_x, 0.0, 1.0) * size.x,
		clampf(normalized_y, 0.0, 1.0) * size.y
	)


func _on_service_registered(service_id: StringName, service: Node) -> void:
	if service_id == EventBus.SERVICE_MAP_MARKERS:
		_bind_map_markers(service)


func _bind_map_markers(service: Node) -> void:
	if service == null:
		return
	_map_markers = service
	if _map_markers.has_signal("markers_changed") and not _map_markers.markers_changed.is_connected(queue_redraw):
		_map_markers.markers_changed.connect(queue_redraw)
