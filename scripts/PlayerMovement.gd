extends CharacterBody2D

@export var max_speed: float = 200.0
@export var acceleration: float = 600.0
@export var friction: float = 1200.0

const OVER_CAPACITY_SPEED_MULTIPLIER := 0.5

var _speed_multiplier := 1.0
var _base_max_speed := 0.0


func _ready() -> void:
	_base_max_speed = max_speed
	InventoryManager.weight_changed.connect(_on_weight_changed)
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)

func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	var current_max_speed := _base_max_speed * _speed_multiplier

	if input_direction != Vector2.ZERO:
		velocity = velocity.move_toward(input_direction * current_max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()


func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	_speed_multiplier = OVER_CAPACITY_SPEED_MULTIPLIER if total_weight > carry_capacity else 1.0
