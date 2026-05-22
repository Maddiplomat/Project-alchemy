extends CharacterBody2D

enum State {
	IDLE,
	PATROL,
	ALERT,
	CHASE,
	ATTACK,
	HIT,
	DEAD,
}

@export var patrol_radius: float = 96.0
@export var detection_radius: float = 180.0
@export var attack_range: float = 48.0
@export var move_speed: float = 60.0
@export var health: int = 120
@export var resistances: Dictionary = {
	&"physical_sharp": 0.4,
	&"physical_blunt": 0.0,
	&"oxidation": 3.0,
	&"electrical": 1.5,
	&"chemical": 1.2,
}

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D

var current_state: State = State.IDLE
var spawn_position: Vector2
var target_position: Vector2


func _ready() -> void:
	add_to_group(&"enemy")
	spawn_position = global_position
	target_position = global_position
	sprite.texture = _build_placeholder_texture()
	navigation_agent.path_desired_distance = 4.0
	navigation_agent.target_desired_distance = attack_range


func _physics_process(_delta: float) -> void:
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.PATROL:
			_update_patrol_velocity()
		State.ALERT:
			velocity = Vector2.ZERO
		State.CHASE:
			_update_chase_velocity()
		State.ATTACK, State.HIT, State.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()


func set_state(new_state: State) -> void:
	current_state = new_state


func set_patrol_target(world_position: Vector2) -> void:
	target_position = spawn_position + (world_position - spawn_position).limit_length(patrol_radius)
	navigation_agent.target_position = target_position


func get_scan_data() -> Dictionary:
	return {
		&"composition": [
			{&"element_id": &"iron", &"pct": 1.0},
		],
		&"weaknesses": [&"oxidation", &"electrical"],
		&"immunities": [&"physical_blunt"],
	}


func _update_patrol_velocity() -> void:
	if navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return

	var next_position := navigation_agent.get_next_path_position()
	velocity = global_position.direction_to(next_position) * move_speed


func _update_chase_velocity() -> void:
	if navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return

	var next_position := navigation_agent.get_next_path_position()
	velocity = global_position.direction_to(next_position) * move_speed


func _build_placeholder_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for y in range(5, 27):
		for x in range(8, 24):
			image.set_pixel(x, y, Color(0.42, 0.48, 0.56, 1.0))

	for y in range(7, 13):
		for x in range(10, 22):
			image.set_pixel(x, y, Color(0.55, 0.62, 0.72, 1.0))

	for y in range(14, 23):
		for x in range(7, 12):
			image.set_pixel(x, y, Color(0.34, 0.39, 0.47, 1.0))
		for x in range(20, 25):
			image.set_pixel(x, y, Color(0.34, 0.39, 0.47, 1.0))

	for y in range(24, 31):
		for x in range(10, 14):
			image.set_pixel(x, y, Color(0.28, 0.32, 0.40, 1.0))
		for x in range(18, 22):
			image.set_pixel(x, y, Color(0.28, 0.32, 0.40, 1.0))

	for x in range(11, 15):
		image.set_pixel(x, 10, Color(0.88, 0.73, 0.34, 1.0))
	for x in range(17, 21):
		image.set_pixel(x, 10, Color(0.88, 0.73, 0.34, 1.0))

	return ImageTexture.create_from_image(image)
