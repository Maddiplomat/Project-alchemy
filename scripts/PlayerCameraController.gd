extends Camera2D
# Smooth follow camera with optional bounds clamping.

@export var smoothing_speed: float = 8.0
@export var bounds_source_path: NodePath = NodePath()
@export var touch_zoom: Vector2 = Vector2(2.1, 2.1)
@export var touch_look_ahead_distance: float = 34.0
@export var look_ahead_smoothing: float = 8.0

var _bounds: Rect2 = Rect2()
var _has_bounds: bool = false
var _zoom_tween: Tween = null
var _desktop_zoom := Vector2.ONE
var _touch_offset := Vector2.ZERO


func _ready() -> void:
	_desktop_zoom = zoom
	position = Vector2.ZERO
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	limit_enabled = false
	var camera_shake := EventBus.get_camera_shake()
	if camera_shake != null and camera_shake.has_method("register_camera"):
		camera_shake.register_camera(self)


func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	_has_bounds = true
	limit_enabled = true
	limit_left = roundi(_bounds.position.x)
	limit_top = roundi(_bounds.position.y)
	limit_right = roundi(_bounds.position.x + _bounds.size.x)
	limit_bottom = roundi(_bounds.position.y + _bounds.size.y)


func _process(delta: float) -> void:
	position_smoothing_speed = smoothing_speed
	_update_touch_camera(delta)


func tween_zoom(target_zoom: Vector2, duration: float = 0.25) -> void:
	if _zoom_tween != null:
		_zoom_tween.kill()

	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_SINE)
	_zoom_tween.set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "zoom", target_zoom, maxf(duration, 0.0))


func _update_touch_camera(delta: float) -> void:
	var prefers_touch := MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()
	if not prefers_touch:
		_touch_offset = _touch_offset.lerp(Vector2.ZERO, clampf(delta * look_ahead_smoothing, 0.0, 1.0))
		offset = _touch_offset
		zoom = zoom.lerp(_desktop_zoom, clampf(delta * 4.0, 0.0, 1.0))
		return

	var player := get_parent() as CharacterBody2D
	var velocity_direction := Vector2.ZERO
	if player != null and player.velocity.length() > 10.0:
		velocity_direction = player.velocity.normalized()

	var touch_pointer_direction := Vector2.ZERO
	if MobileInputRouter != null and MobileInputRouter.has_touch_aim():
		var world_pointer := get_viewport().get_canvas_transform().affine_inverse() * MobileInputRouter.get_touch_aim_screen_position()
		touch_pointer_direction = global_position.direction_to(world_pointer)

	var look_direction := touch_pointer_direction if touch_pointer_direction != Vector2.ZERO else velocity_direction
	var target_offset := look_direction * touch_look_ahead_distance
	_touch_offset = _touch_offset.lerp(target_offset, clampf(delta * look_ahead_smoothing, 0.0, 1.0))
	offset = _touch_offset
	zoom = zoom.lerp(touch_zoom, clampf(delta * 4.0, 0.0, 1.0))
