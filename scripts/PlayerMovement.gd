extends CharacterBody2D

@export var max_speed: float = 200.0
@export var acceleration: float = 600.0
@export var friction: float = 1200.0

const OVER_CAPACITY_SPEED_MULTIPLIER := 0.5
const SPRINT_SPEED_MULTIPLIER := 1.5
const DROP_RISK_THRESHOLD := 1.1
const DROP_RISK_CHANCE := 0.1
const STEP_INTERVAL := 0.3

var _speed_multiplier := 1.0
var _sprint_multiplier := 1.0
var _step_timer := 0.0
var _base_max_speed := 0.0


func _ready() -> void:
	_base_max_speed = max_speed
	InventoryManager.weight_changed.connect(_on_weight_changed)
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)

func _physics_process(delta: float) -> void:
	_sprint_multiplier = SPRINT_SPEED_MULTIPLIER if Input.is_action_pressed(&'sprint') else 1.0
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	var current_max_speed := _base_max_speed * _speed_multiplier * _sprint_multiplier

	if input_direction != Vector2.ZERO:
		velocity = velocity.move_toward(input_direction * current_max_speed, acceleration * delta)
		_handle_sprint_risk(delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_step_timer = 0.0

	move_and_slide()


func _handle_sprint_risk(delta: float) -> void:
	if _sprint_multiplier > 1.0:
		var capacity_ratio = InventoryManager.total_weight / InventoryManager.carry_capacity if InventoryManager.carry_capacity > 0 else 0.0
		if capacity_ratio > DROP_RISK_THRESHOLD:
			_step_timer += delta
			if _step_timer >= STEP_INTERVAL:
				_step_timer = 0.0
				if randf() < DROP_RISK_CHANCE:
					InventoryManager.lose_random_item()
	else:
		_step_timer = 0.0


func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	_speed_multiplier = OVER_CAPACITY_SPEED_MULTIPLIER if total_weight > carry_capacity else 1.0
