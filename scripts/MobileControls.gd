extends Control

const JOYSTICK_RADIUS := 90.0
const JOYSTICK_DEADZONE := 0.16
const POINTER_RADIUS := 96.0

@export var show_on_desktop := false

@onready var move_pad: Control = $MovePad
@onready var move_stick: Control = $MovePad/Stick
@onready var aim_pad: Control = $AimPad
@onready var attack_button: Button = $ButtonsRight/AttackButton
@onready var attack_status_label: Label = $ButtonsRight/AttackStatusLabel
@onready var attack_cooldown_bar: ProgressBar = $ButtonsRight/AttackCooldownBar
@onready var scan_button: Button = $ButtonsRight/ScanButton
@onready var interact_button: Button = $ButtonsRight/InteractButton
@onready var sprint_button: Button = $ButtonsRight/SprintButton
@onready var build_button: Button = $ButtonsRight/BuildButton
@onready var journal_button: Button = $ButtonsTop/JournalButton
@onready var objectives_button: Button = $ButtonsTop/ObjectivesButton
@onready var confirm_button: Button = $BuildButtons/ConfirmButton
@onready var cancel_button: Button = $BuildButtons/CancelButton
@onready var rotate_button: Button = $BuildButtons/RotateButton

var _move_touch_index := -1
var _aim_touch_index := -1
var _move_center := Vector2.ZERO
var _move_stick_origin := Vector2.ZERO
var _player: Node = null


func _ready() -> void:
	visible = show_on_desktop or MobileInputRouter.prefers_touch_controls()
	_move_stick_origin = move_stick.position
	move_pad.gui_input.connect(_on_move_pad_gui_input)
	aim_pad.gui_input.connect(_on_aim_pad_gui_input)
	attack_button.pressed.connect(_on_attack_button_pressed)
	scan_button.toggled.connect(_on_scan_button_toggled)
	interact_button.pressed.connect(func() -> void: MobileInputRouter.tap_action(&"interact"))
	sprint_button.toggled.connect(func(pressed: bool) -> void: MobileInputRouter.set_action_state(&"sprint", pressed))
	build_button.pressed.connect(func() -> void: MobileInputRouter.tap_action(&"toggle_build_mode"))
	journal_button.pressed.connect(func() -> void: MobileInputRouter.tap_action(&"toggle_journal"))
	objectives_button.pressed.connect(func() -> void: MobileInputRouter.tap_action(&"toggle_objectives_panel"))
	confirm_button.pressed.connect(func() -> void: MobileInputRouter.tap_action(&"build_confirm"))
	cancel_button.pressed.connect(func() -> void: MobileInputRouter.tap_action(&"build_cancel"))
	rotate_button.pressed.connect(func() -> void: MobileInputRouter.tap_action(&"build_rotate"))
	_resolve_player()
	_refresh_attack_feedback()


func _exit_tree() -> void:
	_release_move_pad()
	_release_aim_pad()
	if is_instance_valid(sprint_button):
		sprint_button.button_pressed = false
	MobileInputRouter.release_all_actions()


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_build_buttons()
	_refresh_attack_feedback()


func _on_attack_button_pressed() -> void:
	MobileInputRouter.tap_action(&"fire_projectile")


func _on_scan_button_toggled(pressed: bool) -> void:
	MobileInputRouter.set_action_state(&"scan", pressed)


func _on_move_pad_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			if _move_touch_index == -1:
				_move_touch_index = touch_event.index
				_update_move_pad(touch_event.position)
		elif touch_event.index == _move_touch_index:
			_release_move_pad()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _move_touch_index:
			_update_move_pad(drag_event.position)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_move_touch_index = -2
			_update_move_pad(mouse_event.position)
		else:
			_release_move_pad()
	elif event is InputEventMouseMotion and _move_touch_index == -2:
		_update_move_pad((event as InputEventMouseMotion).position)


func _on_aim_pad_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			if _aim_touch_index == -1:
				_aim_touch_index = touch_event.index
				_update_aim_pad(touch_event.position)
		elif touch_event.index == _aim_touch_index:
			_release_aim_pad()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _aim_touch_index:
			_update_aim_pad(drag_event.position)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_aim_touch_index = -2
			_update_aim_pad(mouse_event.position)
		else:
			_release_aim_pad()
	elif event is InputEventMouseMotion and _aim_touch_index == -2:
		_update_aim_pad((event as InputEventMouseMotion).position)


func _update_move_pad(event_position: Vector2) -> void:
	var local_position: Vector2 = _get_pad_local_position(move_pad, event_position)
	_move_center = move_pad.size * 0.5
	var offset: Vector2 = (local_position - _move_center).limit_length(JOYSTICK_RADIUS)
	move_stick.position = _move_stick_origin + offset
	var movement: Vector2 = offset / JOYSTICK_RADIUS
	if movement.length() < JOYSTICK_DEADZONE:
		movement = Vector2.ZERO
	MobileInputRouter.set_virtual_movement(movement)


func _release_move_pad() -> void:
	_move_touch_index = -1
	move_stick.position = _move_stick_origin
	MobileInputRouter.clear_virtual_movement()


func _update_aim_pad(event_position: Vector2) -> void:
	var local_position: Vector2 = _get_pad_local_position(aim_pad, event_position)
	var center: Vector2 = aim_pad.size * 0.5
	var offset: Vector2 = local_position - center
	if offset.length() > POINTER_RADIUS:
		local_position = center + offset.normalized() * POINTER_RADIUS
	var screen_position: Vector2 = aim_pad.get_global_transform_with_canvas() * local_position
	MobileInputRouter.set_touch_aim_screen_position(screen_position, true)


func _release_aim_pad() -> void:
	_aim_touch_index = -1
	MobileInputRouter.clear_touch_aim()


func _get_pad_local_position(pad: Control, event_position: Vector2) -> Vector2:
	# GUI input positions can be canvas-relative on touch devices; accept either
	# canvas or pad-local coordinates so stretched phone layouts stay accurate.
	var transformed_position: Vector2 = pad.get_global_transform_with_canvas().affine_inverse() * event_position
	var pad_bounds: Rect2 = Rect2(Vector2.ZERO, pad.size).grow(24.0)
	if pad_bounds.has_point(transformed_position):
		return transformed_position
	if pad_bounds.has_point(event_position):
		return event_position
	return transformed_position


func _update_build_buttons() -> void:
	var build_active := BuildSystem != null and BuildSystem.is_build_mode_active()
	build_button.text = "Close Build" if build_active else "Build"
	confirm_button.visible = build_active
	cancel_button.visible = build_active
	rotate_button.visible = build_active


func _resolve_player() -> Node:
	var player := GameManager.get_player()
	if player != null:
		_player = player
	return _player


func _refresh_attack_feedback() -> void:
	var player := _resolve_player()
	if player == null:
		attack_button.text = "Attack"
		attack_status_label.text = "No weapon"
		attack_cooldown_bar.value = 0.0
		return

	if not player.has_method("get_touch_attack_label"):
		return

	var attack_label := str(player.get_touch_attack_label())
	var cooldown_remaining := float(player.get_attack_cooldown_remaining()) if player.has_method("get_attack_cooldown_remaining") else 0.0
	var cooldown_duration := float(player.get_attack_cooldown_duration()) if player.has_method("get_attack_cooldown_duration") else 0.0
	var weapon_type := StringName(player.get_touch_weapon_type()) if player.has_method("get_touch_weapon_type") else &"utility"
	var cooldown_ratio := 0.0
	if cooldown_duration > 0.0:
		cooldown_ratio = clampf(cooldown_remaining / cooldown_duration, 0.0, 1.0)

	attack_button.text = "Attack" if cooldown_remaining <= 0.0 else "Recover"
	attack_button.disabled = cooldown_remaining > 0.0
	attack_cooldown_bar.value = cooldown_ratio * 100.0
	attack_status_label.text = _build_attack_status_text(attack_label, weapon_type, cooldown_remaining)


func _build_attack_status_text(attack_label: String, weapon_type: StringName, cooldown_remaining: float) -> String:
	var type_label := String(weapon_type).capitalize()
	if cooldown_remaining > 0.0:
		return "%s | %s | %.1fs" % [attack_label, type_label, cooldown_remaining]
	return "%s | %s ready" % [attack_label, type_label]
