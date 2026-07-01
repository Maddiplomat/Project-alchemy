extends Node

signal shake_started
signal shake_ended

var _intensity: float = 0.0
var _duration: float = 0.0
var _camera: Camera2D = null


func _ready() -> void:
	EventBus.register_service(EventBus.SERVICE_CAMERA_SHAKE, self)


func _exit_tree() -> void:
	EventBus.unregister_service(EventBus.SERVICE_CAMERA_SHAKE, self)


func shake(intensity: float, duration: float) -> void:
	_intensity = maxf(intensity, 0.0)
	_duration = maxf(duration, 0.0)
	if _duration <= 0.0 or _intensity <= 0.0:
		if _camera != null:
			_camera.offset = Vector2.ZERO
		return
	shake_started.emit()


func _process(delta: float) -> void:
	if _duration <= 0.0:
		return

	_duration -= delta
	if _camera != null:
		_camera.offset = Vector2(
			randf_range(-_intensity, _intensity),
			randf_range(-_intensity, _intensity)
		)

	if _duration <= 0.0:
		_duration = 0.0
		if _camera != null:
			_camera.offset = Vector2.ZERO
		shake_ended.emit()


func register_camera(cam: Camera2D) -> void:
	_camera = cam
