extends EnemyAI

signal died(swarmer: CharacterBody2D)

const PATROL_REPATH_SECONDS := 0.45
const ATTRACTION_REPATH_SECONDS := 0.25
const HEALTH_BAR_HIDE_DELAY := 1.6
const LIGHT_WEIGHT := 5.0
const HEAT_WEIGHT := 0.8
const SULFUR_STORAGE_WEIGHT := 0.55

@export var health: int = 18
@export var move_speed: float = 126.0
@export var detection_radius: float = 220.0
@export var attack_range: float = 20.0
@export var attack_damage: int = 4
@export var attack_cooldown_seconds: float = 0.65
@export var light_disrupt_seconds: float = 8.0
@export var resistances: Dictionary = {
	&"electrical": 1.35,
	&"physical_sharp": 0.25,
}

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var enemy_health_bar: ProgressBar = $EnemyHealthBar

var spawn_position := Vector2.ZERO
var target_position := Vector2.ZERO
var _player_target: CharacterBody2D = null
var _max_health := 0
var _repath_timer := 0.0
var _attack_cooldown_timer := 0.0
var _health_bar_hide_timer := 0.0


func _ready() -> void:
	add_to_group(&"enemy")
	spawn_position = global_position
	target_position = global_position
	_max_health = health
	current_state = State.PATROL
	sprite.texture = _build_swarmer_texture()
	navigation_agent.path_desired_distance = 3.0
	navigation_agent.target_desired_distance = attack_range
	_setup_health_bar()
	_refresh_player_target()


func _process(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)
	_repath_timer = maxf(0.0, _repath_timer - delta)
	_refresh_player_target()

	match current_state:
		State.PATROL:
			patrol()
		State.ALERT:
			alert()
		State.ATTACK:
			attack()
		_:
			velocity = Vector2.ZERO

	_update_health_bar_visibility(delta)
	move_and_slide()


func patrol() -> void:
	var attraction_target := _get_light_weighted_attraction_target()
	if attraction_target != Vector2(INF, INF):
		target_position = attraction_target
		current_state = State.ALERT
		return

	if _player_target != null and global_position.distance_to(_player_target.global_position) <= detection_radius:
		target_position = _player_target.global_position
		current_state = State.ALERT
		return

	if global_position.distance_to(target_position) <= 6.0 or _repath_timer <= 0.0:
		target_position = _pick_patrol_target()
		_repath_timer = PATROL_REPATH_SECONDS

	_move_toward(target_position, move_speed * 0.72)


func alert() -> void:
	var attraction_target := _get_light_weighted_attraction_target()
	if attraction_target != Vector2(INF, INF):
		target_position = attraction_target
	elif _player_target != null:
		target_position = _player_target.global_position
	else:
		current_state = State.PATROL
		return

	if global_position.distance_to(target_position) <= attack_range:
		current_state = State.ATTACK
		velocity = Vector2.ZERO
		return

	if _repath_timer <= 0.0:
		navigation_agent.target_position = target_position
		_repath_timer = ATTRACTION_REPATH_SECONDS
	_move_toward(_get_navigation_step(target_position), move_speed)
	_report_lit_zone_presence()


func attack() -> void:
	if _attack_cooldown_timer <= 0.0:
		_disrupt_nearby_light()
		_damage_nearby_player()
		_attack_cooldown_timer = attack_cooldown_seconds

	var attraction_target := _get_light_weighted_attraction_target()
	if attraction_target != Vector2(INF, INF):
		target_position = attraction_target
	elif _player_target != null:
		target_position = _player_target.global_position
	else:
		current_state = State.PATROL
		return

	if global_position.distance_to(target_position) > attack_range * 1.35:
		current_state = State.ALERT


func die() -> void:
	if current_state == State.DEAD:
		return
	current_state = State.DEAD
	_unregister_from_base_defense()
	velocity = Vector2.ZERO
	enemy_health_bar.visible = false
	died.emit(self)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color(0.55, 0.72, 0.76, 0.0), 0.45)
	tween.tween_property(sprite, "scale", Vector2(0.35, 0.35), 0.45)
	await get_tree().create_timer(0.5).timeout
	queue_free()


func get_scan_data() -> Dictionary:
	return {
		&"composition": [
			{&"element_id": &"water", &"pct": 0.34},
			{&"element_id": &"iron", &"pct": 0.22},
			{&"element_id": &"sodium", &"pct": 0.14},
			{&"element_id": &"sulfur", &"pct": 0.30},
		],
		&"weaknesses": [&"physical_sharp", &"chemical"],
		&"immunities": [],
		&"behavior": "Light-drawn swarmer. Prefers powered lights over heat and storage signals.",
	}


func take_damage(amount: int, damage_type: String = "physical_blunt", attacker_pos: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DEAD:
		return
	var final_damage := int(DamageCalculator.calculate(float(amount), damage_type, self, global_position))
	_apply_damage(final_damage, attacker_pos)


func take_resolved_damage(amount: int, _damage_type: String = "physical_blunt", attacker_pos: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DEAD:
		return
	_apply_damage(amount, attacker_pos)


func _apply_damage(amount: int, attacker_pos: Vector2) -> void:
	_show_health_bar_from_combat()
	if amount <= 0:
		_refresh_health_bar()
		return
	health -= amount
	_refresh_health_bar()
	if health <= 0:
		die()
		return
	sprite.modulate = Color(1.8, 2.1, 2.2, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.08)
	if attacker_pos != Vector2.ZERO:
		velocity = attacker_pos.direction_to(global_position) * 42.0


func _get_light_weighted_attraction_target() -> Vector2:
	if GameManager == null or not GameManager.post_tutorial_loop_active:
		return Vector2(INF, INF)
	if BaseThreatDirector == null or not BaseThreatDirector.has_method("get_weighted_enemy_attraction_target"):
		return Vector2(INF, INF)
	return BaseThreatDirector.get_weighted_enemy_attraction_target(
		global_position,
		LIGHT_WEIGHT,
		HEAT_WEIGHT,
		SULFUR_STORAGE_WEIGHT
	)


func _disrupt_nearby_light() -> void:
	for node in get_tree().get_nodes_in_group(&"powered_light"):
		var light := node as Node2D
		if light == null or not is_instance_valid(light):
			continue
		if global_position.distance_to(light.global_position) > attack_range + 8.0:
			continue
		if light.has_method("disrupt"):
			light.call("disrupt", light_disrupt_seconds)
			_spawn_light_disrupt_fx(light.global_position)
			_report_base_breach()
			return


func _damage_nearby_player() -> void:
	if _player_target == null or global_position.distance_to(_player_target.global_position) > attack_range + 4.0:
		return
	var health_system := _player_target.get_node_or_null("HealthSystem")
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(attack_damage, &"electrical", "Light swarmer shock")
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(attack_damage, &"electrical", "Light swarmer shock")


func _refresh_player_target() -> void:
	if _player_target != null and is_instance_valid(_player_target):
		return
	var player := GameManager.get_player()
	if player is CharacterBody2D:
		_player_target = player as CharacterBody2D
		add_collision_exception_with(_player_target)
		_player_target.add_collision_exception_with(self)


func _pick_patrol_target() -> Vector2:
	var angle := randf() * TAU
	var distance := randf_range(20.0, 54.0)
	return spawn_position + Vector2(cos(angle), sin(angle)) * distance


func _move_toward(world_position: Vector2, speed: float) -> void:
	var direction := global_position.direction_to(world_position)
	velocity = direction * speed
	if absf(direction.x) > 0.05:
		sprite.scale.x = 1.0 if direction.x >= 0.0 else -1.0


func _get_navigation_step(destination: Vector2) -> Vector2:
	var navigation_map := navigation_agent.get_navigation_map()
	if navigation_map.is_valid() and not navigation_agent.is_navigation_finished():
		var next_position := navigation_agent.get_next_path_position()
		if global_position.distance_to(next_position) > 0.5:
			return next_position
	return destination


func _report_lit_zone_presence() -> void:
	if BaseDefenseSystem == null or not BaseDefenseSystem.has_method("is_position_in_powered_light"):
		return
	if not BaseDefenseSystem.is_position_in_powered_light(global_position):
		return
	BaseDefenseSystem.report_night_threat(get_instance_id(), global_position)


func _report_base_breach() -> void:
	if BaseThreatDirector != null and BaseThreatDirector.has_method("report_enemy_base_breach"):
		BaseThreatDirector.report_enemy_base_breach(self)


func _unregister_from_base_defense() -> void:
	if BaseDefenseSystem != null and BaseDefenseSystem.has_method("unregister_enemy"):
		BaseDefenseSystem.unregister_enemy(get_instance_id())


func _spawn_light_disrupt_fx(world_position: Vector2) -> void:
	var flash := PointLight2D.new()
	flash.global_position = world_position
	flash.energy = 1.5
	flash.color = Color(0.78, 0.96, 1.0, 1.0)
	get_tree().current_scene.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "energy", 0.0, 0.22)
	tween.finished.connect(flash.queue_free, CONNECT_ONE_SHOT)


func _build_swarmer_texture() -> Texture2D:
	var image := Image.create(20, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var wing := Color(0.50, 0.78, 0.86, 0.76)
	var body := Color(0.12, 0.18, 0.20, 1.0)
	var glow := Color(0.82, 1.0, 1.0, 1.0)
	for y in range(4, 11):
		for x in range(2, 8):
			if Vector2(float(x), float(y)).distance_to(Vector2(5.0, 7.0)) <= 4.0:
				image.set_pixel(x, y, wing)
		for x in range(12, 18):
			if Vector2(float(x), float(y)).distance_to(Vector2(15.0, 7.0)) <= 4.0:
				image.set_pixel(x, y, wing)
	for y in range(3, 13):
		for x in range(8, 12):
			image.set_pixel(x, y, body)
	for pixel: Vector2i in [Vector2i(9, 4), Vector2i(10, 4), Vector2i(9, 8), Vector2i(10, 8)]:
		image.set_pixel(pixel.x, pixel.y, glow)
	return ImageTexture.create_from_image(image)


func _setup_health_bar() -> void:
	if enemy_health_bar == null:
		return
	enemy_health_bar.min_value = 0.0
	enemy_health_bar.max_value = float(_max_health)
	enemy_health_bar.value = float(health)
	enemy_health_bar.visible = false
	enemy_health_bar.show_percentage = false


func _show_health_bar_from_combat() -> void:
	if enemy_health_bar == null:
		return
	enemy_health_bar.visible = true
	_health_bar_hide_timer = HEALTH_BAR_HIDE_DELAY


func _refresh_health_bar() -> void:
	if enemy_health_bar == null:
		return
	enemy_health_bar.value = float(maxi(health, 0))


func _update_health_bar_visibility(delta: float) -> void:
	if enemy_health_bar == null or not enemy_health_bar.visible:
		return
	_health_bar_hide_timer = maxf(0.0, _health_bar_hide_timer - delta)
	if _health_bar_hide_timer <= 0.0:
		enemy_health_bar.visible = false
