extends Node

signal shake(strength: float, duration: float)

@export var max_offset: float = 24.0

var _rng := RandomNumberGenerator.new()
var _current_strength := 0.0
var _shake_tween: Tween
var _active_camera: Camera2D
var _base_offset := Vector2.ZERO
var _applied_offset := Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	shake.connect(_on_shake)


func _process(_delta: float) -> void:
	if _current_strength <= 0.0:
		_clear_camera_offset()
		return

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		_clear_camera_offset()
		return

	if camera != _active_camera:
		_clear_camera_offset()
		_active_camera = camera
		_base_offset = camera.offset

	_applied_offset = _random_unit_vector() * minf(_current_strength, max_offset)
	_active_camera.offset = _base_offset + _applied_offset


func _on_shake(strength: float, duration: float) -> void:
	if _shake_tween:
		_shake_tween.kill()

	_current_strength = maxf(strength, 0.0)
	if duration <= 0.0 or _current_strength <= 0.0:
		_current_strength = 0.0
		_clear_camera_offset()
		return

	_shake_tween = create_tween()
	_shake_tween.set_trans(Tween.TRANS_EXPO)
	_shake_tween.set_ease(Tween.EASE_OUT)
	_shake_tween.tween_method(_set_current_strength, _current_strength, 0.0, duration)
	_shake_tween.finished.connect(_on_shake_finished)


func _set_current_strength(value: float) -> void:
	_current_strength = value


func _on_shake_finished() -> void:
	_current_strength = 0.0
	_clear_camera_offset()


func _clear_camera_offset() -> void:
	if _active_camera != null:
		_active_camera.offset = _base_offset
	_active_camera = null
	_base_offset = Vector2.ZERO
	_applied_offset = Vector2.ZERO


func _random_unit_vector() -> Vector2:
	return Vector2.from_angle(_rng.randf_range(0.0, TAU))
