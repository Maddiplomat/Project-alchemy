extends CharacterBody2D

signal patrol_waypoint_reached(waypoint_index: int)
signal alert_triggered(reason: StringName)

enum State {
	IDLE,
	PATROL,
	ALERT,
	CHASE,
	ATTACK,
	HIT,
	DEAD,
}

const PATROL_WAIT_SECONDS := 1.5
const SCANNER_ALERT_RADIUS := 150.0
const CHASE_REPATH_INTERVAL := 0.3

@export var patrol_radius: float = 96.0
@export var detection_radius: float = 180.0
@export var attack_range: float = 48.0
@export var move_speed: float = 60.0
@export var health: int = 120
@export var patrol_waypoint_a: Vector2 = Vector2(-48.0, 0.0)
@export var patrol_waypoint_b: Vector2 = Vector2(48.0, 0.0)
@export var resistances: Dictionary = {
	&"physical_sharp": 0.4,
	&"physical_blunt": 0.0,
	&"oxidation": 3.0,
	&"electrical": 1.5,
	&"chemical": 1.2,
}

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/CollisionShape2D
@onready var alert_audio_player: AudioStreamPlayer2D = $AlertAudioPlayer2D

var current_state: State = State.PATROL
var spawn_position: Vector2
var target_position: Vector2
var _patrol_points: Array[Vector2] = []
var _current_patrol_index := 0
var _patrol_wait_timer := 0.0
var _chase_repath_timer := 0.0
var _player_target: CharacterBody2D = null
var _attack_cooldown_timer := 0.0
var _hit_timer := 0.0


func _ready() -> void:
	add_to_group(&"enemy")
	spawn_position = global_position
	target_position = global_position
	sprite.texture = _build_placeholder_texture()
	navigation_agent.path_desired_distance = 4.0
	navigation_agent.target_desired_distance = attack_range
	_patrol_points = [
		spawn_position + patrol_waypoint_a.limit_length(patrol_radius),
		spawn_position + patrol_waypoint_b.limit_length(patrol_radius),
	]
	_apply_detection_radius()
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	_connect_scanner_tools()
	_build_alert_audio_stream()
	_set_patrol_destination(_current_patrol_index)


func _physics_process(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
	_step_state(delta)
	move_and_slide()


func simulate_step(delta: float) -> void:
	_step_state(delta)
	global_position += velocity * delta


func _step_state(delta: float) -> void:
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.PATROL:
			_update_patrol_velocity(delta)
		State.ALERT:
			_update_alert_state(delta)
		State.CHASE:
			_update_chase_velocity(delta)
		State.ATTACK:
			_update_attack_state(delta)
		State.HIT:
			_update_hit_state(delta)
		State.DEAD:
			velocity = Vector2.ZERO


func set_state(new_state: State) -> void:
	if current_state == new_state:
		return

	current_state = new_state
	if current_state == State.PATROL:
		_patrol_wait_timer = 0.0
		_set_patrol_destination(_current_patrol_index)
	elif current_state == State.ALERT:
		velocity = Vector2.ZERO
		_chase_repath_timer = CHASE_REPATH_INTERVAL
	elif current_state == State.CHASE:
		_chase_repath_timer = 0.0
	elif current_state == State.ATTACK:
		velocity = Vector2.ZERO
	elif current_state == State.HIT:
		pass


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


func _update_patrol_velocity(delta: float) -> void:
	if _patrol_wait_timer > 0.0:
		_patrol_wait_timer = maxf(0.0, _patrol_wait_timer - delta)
		velocity = Vector2.ZERO
		if _patrol_wait_timer <= 0.0:
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
			_set_patrol_destination(_current_patrol_index)
		return

	if global_position.distance_to(target_position) <= navigation_agent.path_desired_distance:
		_patrol_wait_timer = PATROL_WAIT_SECONDS
		patrol_waypoint_reached.emit(_current_patrol_index)
		velocity = Vector2.ZERO
		return

	var next_position := _get_navigation_step(target_position)
	velocity = global_position.direction_to(next_position) * move_speed


func _update_alert_state(delta: float) -> void:
	velocity = Vector2.ZERO
	_chase_repath_timer = maxf(0.0, _chase_repath_timer - delta)
	if is_zero_approx(_chase_repath_timer):
		set_state(State.CHASE)


func _update_chase_velocity(delta: float) -> void:
	if not is_instance_valid(_player_target):
		_player_target = _find_player()
	if not is_instance_valid(_player_target):
		set_state(State.PATROL)
		return

	if global_position.distance_to(_player_target.global_position) <= attack_range:
		set_state(State.ATTACK)
		velocity = Vector2.ZERO
		return

	_chase_repath_timer = maxf(0.0, _chase_repath_timer - delta)
	if _chase_repath_timer <= 0.0:
		navigation_agent.target_position = _player_target.global_position
		target_position = _player_target.global_position
		_chase_repath_timer = CHASE_REPATH_INTERVAL

	var next_position := _get_navigation_step(target_position)
	velocity = global_position.direction_to(next_position) * move_speed


func _update_attack_state(_delta: float) -> void:
	if _attack_cooldown_timer <= 0.0:
		_perform_ground_slam()
		_attack_cooldown_timer = 0.8
	
	if not is_instance_valid(_player_target) or global_position.distance_to(_player_target.global_position) > attack_range:
		set_state(State.CHASE)


func _perform_ground_slam() -> void:
	var space_state = get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = attack_range
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, global_position)
	query.collision_mask = 1
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res.collider
		if col.name == "Player":
			if col.has_node("HealthSystem"):
				col.get_node("HealthSystem").take_damage(12, "physical_blunt")
			elif col.has_method("take_damage"):
				col.take_damage(12, "physical_blunt")


func _update_hit_state(delta: float) -> void:
	_hit_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, delta * 300)
	if _hit_timer <= 0.0:
		set_state(State.CHASE)


func take_damage(amount: int, damage_type: String = "physical_blunt", attacker_pos: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DEAD:
		return
		
	var final_damage = int(DamageCalculator.calculate(float(amount), damage_type, self)) if ClassDB.class_exists("DamageCalculator") else amount
	if final_damage <= 0:
		return
		
	health -= final_damage
	if health <= 0:
		die()
	else:
		set_state(State.HIT)
		_hit_timer = 0.3
		sprite.modulate = Color(10, 10, 10, 1)
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)
		if attacker_pos != Vector2.ZERO:
			velocity = attacker_pos.direction_to(global_position) * (32.0 / 0.3)


func die() -> void:
	set_state(State.DEAD)
	
	var rect = ColorRect.new()
	rect.color = Color("8b4513")
	rect.size = sprite.texture.get_size() if sprite.texture else Vector2(32, 32)
	rect.position = -rect.size / 2.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	
	var tween = create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 1.5)
	tween.parallel().tween_property(rect, "modulate:a", 0.0, 1.5)
	
	if randf() <= 0.8:
		InventoryManager.add_element("iron", 3, 1.0)
	if randf() <= 0.4:
		InventoryManager.add_element("water", 1, 1.0)
		
	await get_tree().create_timer(1.5).timeout
	queue_free()


func _set_patrol_destination(index: int) -> void:
	if _patrol_points.is_empty():
		return

	target_position = _patrol_points[index]
	navigation_agent.target_position = target_position


func _get_navigation_step(destination: Vector2) -> Vector2:
	var navigation_map := navigation_agent.get_navigation_map()
	if navigation_map.is_valid() and not navigation_agent.is_navigation_finished():
		var next_position := navigation_agent.get_next_path_position()
		var desired_direction := global_position.direction_to(destination)
		var path_direction := global_position.direction_to(next_position)
		if global_position.distance_to(next_position) > 0.5 and desired_direction.dot(path_direction) > 0.1:
			return next_position
	return destination


func _apply_detection_radius() -> void:
	if detection_shape == null:
		return
	var circle_shape := detection_shape.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = detection_radius


func _connect_scanner_tools() -> void:
	for scanner in get_tree().get_nodes_in_group(&"scanner_tool"):
		var scanner_tool := scanner as Node
		if scanner_tool == null:
			continue
		var scan_started_callable := Callable(self, "_on_scanner_scan_started")
		if not scanner_tool.scan_started.is_connected(scan_started_callable):
			scanner_tool.scan_started.connect(scan_started_callable)


func _find_player() -> CharacterBody2D:
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player is CharacterBody2D:
		return player as CharacterBody2D
	return null


func _trigger_alert(reason: StringName, player: CharacterBody2D) -> void:
	if current_state == State.DEAD:
		return

	_player_target = player
	_face_target(player.global_position)
	_play_alert_sfx()
	alert_triggered.emit(reason)
	if current_state != State.CHASE and current_state != State.ATTACK:
		set_state(State.ALERT)


func _face_target(world_position: Vector2) -> void:
	var direction := world_position - global_position
	if direction.length_squared() <= 0.001:
		return
	sprite.rotation = direction.angle()


func _play_alert_sfx() -> void:
	if alert_audio_player.stream == null:
		return
	alert_audio_player.stop()
	alert_audio_player.play()


func _build_alert_audio_stream() -> void:
	var sample_rate := 22050
	var duration_seconds := 0.12
	var frame_count := int(sample_rate * duration_seconds)
	var data := PackedByteArray()
	data.resize(frame_count * 2)

	for frame in range(frame_count):
		var t := float(frame) / float(sample_rate)
		var envelope := 1.0 - (float(frame) / float(frame_count))
		var sample: float = sin(TAU * 660.0 * t) * envelope * 0.35
		var sample_value := int(clampi(int(sample * 32767.0), -32768, 32767))
		var packed_value := sample_value & 0xffff
		data[frame * 2] = packed_value & 0xff
		data[frame * 2 + 1] = (packed_value >> 8) & 0xff

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	alert_audio_player.stream = stream


func _on_detection_body_entered(body: Node) -> void:
	if body.name != "Player" or not body is CharacterBody2D:
		return
	_trigger_alert(&"player_detected", body as CharacterBody2D)


func _on_detection_body_exited(body: Node) -> void:
	if body == _player_target and current_state == State.CHASE:
		_player_target = null


func _on_scanner_scan_started(origin: Vector2) -> void:
	var player := _find_player()
	if player == null:
		return
	if origin.distance_to(global_position) > SCANNER_ALERT_RADIUS:
		return
	_trigger_alert(&"scanner_hum", player)


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
