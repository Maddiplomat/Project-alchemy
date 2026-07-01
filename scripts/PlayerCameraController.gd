extends Camera2D
# Smooth follow camera with optional bounds clamping.

@export var smoothing_speed: float = 8.0
@export var bounds_source_path: NodePath = NodePath()

var _bounds: Rect2 = Rect2()
var _has_bounds: bool = false
var _zoom_tween: Tween = null


func _ready() -> void:
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


func _process(_delta: float) -> void:
	position_smoothing_speed = smoothing_speed


func tween_zoom(target_zoom: Vector2, duration: float = 0.25) -> void:
	if _zoom_tween != null:
		_zoom_tween.kill()

	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_SINE)
	_zoom_tween.set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "zoom", target_zoom, maxf(duration, 0.0))
