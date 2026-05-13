extends CharacterBody2D

@export var max_speed: float = 200.0
@export var acceleration: float = 600.0
@export var friction: float = 1200.0

const OVER_CAPACITY_SPEED_MULTIPLIER := 0.5
const SPRINT_SPEED_MULTIPLIER := 1.5
@export var sprint_drop_chance: float = 0.002

signal drop_item(slot_index: int)
signal input_paused_changed(is_paused: bool)

var _speed_multiplier := 1.0
var _sprint_multiplier := 1.0
var _step_timer := 0.0
var _base_max_speed := 0.0

var _input_paused := false


func _ready() -> void:
	_base_max_speed = max_speed
	drop_item.connect(_on_drop_item)
	InventoryManager.weight_changed.connect(_on_weight_changed)
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)

func _physics_process(delta: float) -> void:
	if _input_paused:
		velocity = Vector2.ZERO
		_step_timer = 0.0
		move_and_slide()
		return

	_sprint_multiplier = SPRINT_SPEED_MULTIPLIER if Input.is_action_pressed(&'sprint') else 1.0
	_handle_sprint_risk()
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	var current_max_speed := _base_max_speed * _speed_multiplier * _sprint_multiplier

	if input_direction != Vector2.ZERO and not _input_paused:
		velocity = velocity.move_toward(input_direction * current_max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_step_timer = 0.0

	move_and_slide()


func _handle_sprint_risk() -> void:
	if _sprint_multiplier <= 1.0:
		return
	if not InventoryManager.is_over_capacity():
		return
	if randf() >= sprint_drop_chance:
		return

	var random_slot := randi() % InventoryManager.DEFAULT_SLOT_COUNT
	drop_item.emit(random_slot)


func _on_drop_item(slot_index: int) -> void:
	var slot_item := InventoryManager.get_slot_item(slot_index)
	if slot_item.is_empty():
		return

	InventoryManager.remove_item(StringName(slot_item.get("id", "")), 1)


func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	_speed_multiplier = OVER_CAPACITY_SPEED_MULTIPLIER if total_weight > carry_capacity else 1.0


func pause_input() -> void:
	_input_paused = true
	_sprint_multiplier = 1.0
	velocity = Vector2.ZERO
	input_paused_changed.emit(true)


func resume_input() -> void:
	_input_paused = false
	input_paused_changed.emit(false)


func is_input_paused() -> bool:
	return _input_paused
