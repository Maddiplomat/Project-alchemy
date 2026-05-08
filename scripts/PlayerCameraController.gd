extends Camera2D

@export var development_world_bounds: Rect2 = Rect2(Vector2(-1024.0, -1024.0), Vector2(2048.0, 2048.0))
@export var bounds_source_path: NodePath
@export var idle_smoothing_speed: float = 4.0
@export var moving_smoothing_speed: float = 9.0
@export var max_reference_speed: float = 200.0
@export var smoothing_response: float = 12.0

var _zoom_tween: Tween


func _ready() -> void:
	position_smoothing_enabled = true
	limit_enabled = true
	position_smoothing_speed = idle_smoothing_speed
	_apply_world_bounds(_get_world_bounds())


func _physics_process(delta: float) -> void:
	_apply_dynamic_smoothing(delta)
	_apply_world_bounds(_get_world_bounds())


func tween_zoom(target_zoom: Vector2, duration: float = 0.25) -> void:
	if _zoom_tween:
		_zoom_tween.kill()

	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_SINE)
	_zoom_tween.set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "zoom", target_zoom, maxf(duration, 0.0))


func _apply_dynamic_smoothing(delta: float) -> void:
	var speed_ratio := 0.0
	if max_reference_speed > 0.0:
		speed_ratio = clampf(_get_target_speed() / max_reference_speed, 0.0, 1.0)

	var target_smoothing_speed := lerpf(idle_smoothing_speed, moving_smoothing_speed, speed_ratio)
	var response_weight := 1.0
	if smoothing_response > 0.0 and delta > 0.0:
		response_weight = 1.0 - exp(-smoothing_response * delta)

	position_smoothing_speed = lerpf(position_smoothing_speed, target_smoothing_speed, response_weight)


func _get_target_speed() -> float:
	var parent := get_parent()
	if parent == null:
		return 0.0

	var parent_velocity = parent.get("velocity")
	if parent_velocity is Vector2:
		return parent_velocity.length()

	return 0.0


func _get_world_bounds() -> Rect2:
	var bounds_source := get_node_or_null(bounds_source_path)
	if bounds_source != null and bounds_source.has_method("get_world_bounds"):
		var source_bounds = bounds_source.call("get_world_bounds")
		if source_bounds is Rect2:
			return source_bounds

	return development_world_bounds


func _apply_world_bounds(world_bounds: Rect2) -> void:
	limit_left = roundi(world_bounds.position.x)
	limit_top = roundi(world_bounds.position.y)
	limit_right = roundi(world_bounds.position.x + world_bounds.size.x)
	limit_bottom = roundi(world_bounds.position.y + world_bounds.size.y)
