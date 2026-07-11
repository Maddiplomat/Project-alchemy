extends Node

signal input_mode_changed(input_mode: StringName)

const INPUT_MODE_DESKTOP := &"desktop"
const INPUT_MODE_TOUCH := &"touch"

var _virtual_movement := Vector2.ZERO
var _touch_pointer_screen_position := Vector2.ZERO
var _touch_pointer_active := false
var _touch_aim_screen_position := Vector2.ZERO
var _touch_aim_active := false
var _action_states: Dictionary = {}
var _input_mode: StringName = INPUT_MODE_DESKTOP


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_input_mode(INPUT_MODE_TOUCH)
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:
		_set_input_mode(INPUT_MODE_DESKTOP)


func prefers_touch_controls() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func get_input_mode() -> StringName:
	return _input_mode


func is_touch_mode() -> bool:
	return _input_mode == INPUT_MODE_TOUCH


func set_virtual_movement(direction: Vector2) -> void:
	_virtual_movement = direction.limit_length(1.0)
	if _virtual_movement.length_squared() > 0.0:
		_set_input_mode(INPUT_MODE_TOUCH)


func clear_virtual_movement() -> void:
	_virtual_movement = Vector2.ZERO


func get_virtual_movement() -> Vector2:
	return _virtual_movement


func has_virtual_movement() -> bool:
	return _virtual_movement.length_squared() > 0.0


func set_touch_pointer_screen_position(screen_position: Vector2, active: bool = true) -> void:
	_touch_pointer_screen_position = screen_position
	_touch_pointer_active = active
	if active:
		_set_input_mode(INPUT_MODE_TOUCH)


func clear_touch_pointer() -> void:
	_touch_pointer_active = false


func has_touch_pointer() -> bool:
	return _touch_pointer_active


func get_touch_pointer_screen_position() -> Vector2:
	return _touch_pointer_screen_position


func set_touch_aim_screen_position(screen_position: Vector2, active: bool = true) -> void:
	_touch_aim_screen_position = screen_position
	_touch_aim_active = active
	set_touch_pointer_screen_position(screen_position, active)


func clear_touch_aim() -> void:
	_touch_aim_active = false
	clear_touch_pointer()


func has_touch_aim() -> bool:
	return _touch_aim_active


func get_touch_aim_screen_position() -> Vector2:
	return _touch_aim_screen_position


func tap_action(action_name: StringName) -> void:
	_emit_action_event(action_name, true)
	_emit_action_event(action_name, false)


func set_action_state(action_name: StringName, pressed: bool) -> void:
	var current_state := bool(_action_states.get(action_name, false))
	if current_state == pressed:
		return
	_action_states[action_name] = pressed
	_emit_action_event(action_name, pressed)


func release_all_actions() -> void:
	for action_name: Variant in _action_states.keys():
		if bool(_action_states[action_name]):
			_emit_action_event(StringName(action_name), false)
	_action_states.clear()


func _emit_action_event(action_name: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
	if pressed:
		_set_input_mode(INPUT_MODE_TOUCH)


func _set_input_mode(next_mode: StringName) -> void:
	if _input_mode == next_mode:
		return
	_input_mode = next_mode
	input_mode_changed.emit(_input_mode)
