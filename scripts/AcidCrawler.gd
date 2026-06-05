extends CharacterBody2D

signal died(crawler: CharacterBody2D)

enum State {
	IDLE,
	PATROL,
	BURROW,
	EMERGE,
	ATTACK,
	DEAD,
}

const AcidSpitScript := preload("res://scripts/AcidSpit.gd")
const DAY_PATROL_SPEED := 40.0
const NIGHT_PATROL_SPEED := 48.0
const DAY_BURROW_SPEED := 90.0
const NIGHT_BURROW_SPEED := 104.0
const PATROL_RADIUS := 64.0
const DETECTION_RADIUS := 240.0
const REBURROW_RADIUS := 200.0
const MAX_PURSUIT_RADIUS := 320.0
const ATTACK_RANGE := 96.0
const EMERGE_WARNING_SECONDS := 2.0
const ATTACK_COOLDOWN_SECONDS := 1.35
const HEALTH_BAR_HIDE_DELAY := 2.0

@export var health: int = 48

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var enemy_health_bar: ProgressBar = $EnemyHealthBar
@onready var scan_proxy: Area2D = $ScanProxy
@onready var scan_proxy_shape: CollisionShape2D = $ScanProxy/CollisionShape2D

var current_state: State = State.IDLE
var spawn_position := Vector2.ZERO
var target_position := Vector2.ZERO
var _player_target: CharacterBody2D = null
var _patrol_target := Vector2.ZERO
var _patrol_wait_timer := 0.0
var _burrow_target_position := Vector2.ZERO
var _emerge_warning_timer := 0.0
var _attack_cooldown_timer := 0.0
var _max_health := 0
var _health_bar_hide_timer := 0.0
var _subsurface_signal := false
var _night_active := false
var _patrol_speed := DAY_PATROL_SPEED
var _burrow_speed := DAY_BURROW_SPEED
var _returning_to_spawn := false


func _ready() -> void:
	add_to_group(&"enemy")
	_max_health = health
	spawn_position = global_position
	target_position = global_position
	_patrol_target = global_position
	_burrow_target_position = global_position
	sprite.texture = _build_crawler_texture()
	navigation_agent.path_desired_distance = 3.0
	navigation_agent.target_desired_distance = 6.0
	_setup_health_bar()
	_sync_scan_proxy()

	if GameManager.has_signal("day_started"):
		GameManager.day_started.connect(_on_day_started)
	if GameManager.has_signal("night_started"):
		GameManager.night_started.connect(_on_night_started)

	if GameManager.has_method("is_night") and GameManager.is_night():
		_on_night_started()
	else:
		_on_day_started()


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)

	_refresh_player_target()
	_step_state(delta)
	_update_health_bar_visibility(delta)
	move_and_slide()


func get_scan_data() -> Dictionary:
	var scan_data := {
		&"composition": [
			{&"element_id": &"sulfur", &"pct": 0.52},
			{&"element_id": &"stone", &"pct": 0.33},
			{&"element_id": &"water", &"pct": 0.15},
		],
		&"weaknesses": [&"physical_sharp", &"electrical"],
		&"immunities": [&"chemical"],
	}
	if _is_subsurface_state():
		scan_data[&"subsurface_signal"] = true
	return scan_data


func take_damage(amount: int, damage_type: String = "physical_blunt", attacker_pos: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DEAD:
		return
	var final_damage := int(DamageCalculator.calculate(float(amount), damage_type, self, global_position))
	_apply_damage(final_damage, attacker_pos)


func take_resolved_damage(amount: int, _damage_type: String = "physical_blunt", attacker_pos: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DEAD:
		return
	_apply_damage(amount, attacker_pos)


func die() -> void:
	if current_state == State.DEAD:
		return

	current_state = State.DEAD
	velocity = Vector2.ZERO
	_set_surface_visible(true)
	_sync_scan_proxy()
	enemy_health_bar.visible = false
	died.emit(self)
	_drop_limestone()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color(0.44, 0.48, 0.42, 0.88), 1.5)
	tween.tween_property(sprite, "scale", Vector2(1.3, 0.35), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(1.5).timeout
	queue_free()


func _step_state(delta: float) -> void:
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.PATROL:
			_update_patrol_state(delta)
		State.BURROW:
			_update_burrow_state()
		State.EMERGE:
			_update_emerge_state(delta)
		State.ATTACK:
			_update_attack_state()
		State.DEAD:
			velocity = Vector2.ZERO


func _update_patrol_state(delta: float) -> void:
	if _player_target != null and global_position.distance_to(_player_target.global_position) <= DETECTION_RADIUS:
		_begin_burrow(_get_player_tile_center())
		return

	if _patrol_wait_timer > 0.0:
		_patrol_wait_timer = maxf(0.0, _patrol_wait_timer - delta)
		velocity = Vector2.ZERO
		if _patrol_wait_timer <= 0.0:
			_choose_patrol_target()
		return

	if global_position.distance_to(_patrol_target) <= 5.0:
		_patrol_wait_timer = 0.8
		velocity = Vector2.ZERO
		return

	_face_target(_patrol_target)
	velocity = global_position.direction_to(_patrol_target) * _patrol_speed


func _update_burrow_state() -> void:
	if _returning_to_spawn:
		_burrow_target_position = spawn_position
	elif _player_target != null and _player_target.global_position.distance_to(spawn_position) <= MAX_PURSUIT_RADIUS:
		_burrow_target_position = _get_player_tile_center()
	else:
		_burrow_target_position = spawn_position
		_returning_to_spawn = true
	navigation_agent.target_position = _burrow_target_position
	target_position = _burrow_target_position

	var next_position := _get_navigation_step(_burrow_target_position)
	velocity = global_position.direction_to(next_position) * _burrow_speed
	if global_position.distance_to(_burrow_target_position) <= 6.0:
		if _returning_to_spawn:
			_finish_return_to_spawn()
		else:
			_start_emerge_warning()


func _update_emerge_state(delta: float) -> void:
	velocity = Vector2.ZERO

	_emerge_warning_timer = maxf(0.0, _emerge_warning_timer - delta)
	if _emerge_warning_timer <= 0.0:
		_finish_emerge()


func _update_attack_state() -> void:
	if _player_target == null:
		current_state = State.PATROL
		_choose_patrol_target()
		return

	var distance_to_player := global_position.distance_to(_player_target.global_position)
	if distance_to_player > REBURROW_RADIUS:
		_begin_burrow(spawn_position, true)
		return
	if global_position.distance_to(spawn_position) > MAX_PURSUIT_RADIUS:
		_begin_burrow(spawn_position, true)
		return
	if _player_target.global_position.distance_to(spawn_position) > MAX_PURSUIT_RADIUS:
		_begin_burrow(spawn_position, true)
		return

	_face_target(_player_target.global_position)
	if distance_to_player > ATTACK_RANGE:
		velocity = global_position.direction_to(_player_target.global_position) * (_patrol_speed + 12.0)
		return

	velocity = Vector2.ZERO
	if _attack_cooldown_timer <= 0.0:
		_fire_acid_spit()
		_attack_cooldown_timer = ATTACK_COOLDOWN_SECONDS


func _begin_burrow(destination: Vector2, return_to_spawn: bool = false) -> void:
	current_state = State.BURROW
	_burrow_target_position = destination
	_returning_to_spawn = return_to_spawn
	_subsurface_signal = false
	_set_surface_visible(false)
	_sync_scan_proxy()
	navigation_agent.target_position = _burrow_target_position


func _start_emerge_warning() -> void:
	current_state = State.EMERGE
	velocity = Vector2.ZERO
	global_position = _burrow_target_position
	_emerge_warning_timer = EMERGE_WARNING_SECONDS
	_subsurface_signal = true
	_set_surface_visible(false)
	_sync_scan_proxy()
	_spawn_emerge_warning_fx(_burrow_target_position)
	if CameraShake != null and CameraShake.has_signal("shake"):
		CameraShake.shake.emit(0.25, 0.4)


func _finish_emerge() -> void:
	_subsurface_signal = false
	_set_surface_visible(true)
	_sync_scan_proxy()
	_attack_cooldown_timer = 0.0
	_returning_to_spawn = false
	current_state = State.ATTACK


func _set_surface_visible(is_visible: bool) -> void:
	sprite.visible = is_visible
	collision_shape.disabled = not is_visible
	if enemy_health_bar != null and not is_visible:
		enemy_health_bar.visible = false


func _sync_scan_proxy() -> void:
	var scan_enabled := current_state != State.DEAD
	_set_scan_proxy_enabled(scan_enabled)


func _is_subsurface_state() -> bool:
	return current_state == State.BURROW or current_state == State.EMERGE


func _finish_return_to_spawn() -> void:
	_returning_to_spawn = false
	_subsurface_signal = false
	_set_surface_visible(true)
	_sync_scan_proxy()
	_player_target = null
	current_state = State.PATROL
	_choose_patrol_target()


func _set_scan_proxy_enabled(enabled: bool) -> void:
	if scan_proxy == null or scan_proxy_shape == null:
		return
	scan_proxy.monitoring = enabled
	scan_proxy.monitorable = enabled
	scan_proxy_shape.disabled = not enabled


func _choose_patrol_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) + int(global_position.x) * 17 + int(global_position.y) * 31
	var offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(20.0, PATROL_RADIUS)
	_patrol_target = spawn_position + offset


func _fire_acid_spit() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var target := _player_target.global_position if _player_target != null else global_position + Vector2.RIGHT * ATTACK_RANGE
	var origin := global_position + Vector2(0.0, -12.0)
	AcidSpitScript.spawn(parent, origin, target)


func _apply_damage(amount: int, attacker_pos: Vector2) -> void:
	if amount <= 0:
		return
	_show_health_bar_from_combat()
	health -= amount
	_refresh_health_bar()
	if health <= 0:
		die()
		return

	sprite.modulate = Color(1.7, 1.7, 1.7, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.12)
	if attacker_pos != Vector2.ZERO and current_state != State.BURROW:
		velocity = attacker_pos.direction_to(global_position) * 45.0


func _refresh_player_target() -> void:
	if _player_target != null and is_instance_valid(_player_target):
		return
	_player_target = _find_player()


func _find_player() -> CharacterBody2D:
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player is CharacterBody2D:
		return player as CharacterBody2D
	return null


func _get_player_tile_center() -> Vector2:
	if _player_target == null:
		return spawn_position
	var ground := get_tree().current_scene.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return _player_target.global_position
	var local_position := ground.to_local(_player_target.global_position)
	var coords := ground.local_to_map(local_position)
	return ground.to_global(ground.map_to_local(coords))


func _get_navigation_step(destination: Vector2) -> Vector2:
	var navigation_map := navigation_agent.get_navigation_map()
	if navigation_map.is_valid() and not navigation_agent.is_navigation_finished():
		var next_position := navigation_agent.get_next_path_position()
		if global_position.distance_to(next_position) > 0.5:
			return next_position
	return destination


func _drop_limestone() -> void:
	if randf() > 0.5:
		return
	var spawn_system := get_tree().current_scene.get_node_or_null("ElementSpawnSystem")
	if spawn_system != null and spawn_system.has_method("spawn_world_pickup"):
		spawn_system.spawn_world_pickup(&"limestone", global_position, 1)


func _on_day_started() -> void:
	_night_active = false
	_patrol_speed = DAY_PATROL_SPEED
	_burrow_speed = DAY_BURROW_SPEED
	if current_state == State.DEAD:
		return
	if current_state == State.IDLE:
		current_state = State.PATROL
		_set_surface_visible(true)
		_choose_patrol_target()


func _on_night_started() -> void:
	_night_active = true
	_patrol_speed = NIGHT_PATROL_SPEED
	_burrow_speed = NIGHT_BURROW_SPEED
	if current_state == State.DEAD:
		return
	if current_state == State.IDLE:
		current_state = State.PATROL
		_set_surface_visible(true)
		_choose_patrol_target()


func _face_target(world_position: Vector2) -> void:
	var delta := world_position - global_position
	if absf(delta.x) > 1.0:
		sprite.scale.x = 1.0 if delta.x >= 0.0 else -1.0


func _spawn_emerge_warning_fx(world_position: Vector2) -> void:
	var particles := GPUParticles2D.new()
	particles.position = world_position
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 28
	particles.lifetime = 0.7
	particles.explosiveness = 1.0
	particles.local_coords = false

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 6.0
	material.emission_ring_inner_radius = 2.0
	material.direction = Vector3.UP
	material.spread = 55.0
	material.initial_velocity_min = 24.0
	material.initial_velocity_max = 56.0
	material.gravity = Vector3(0.0, 90.0, 0.0)
	material.scale_min = 1.8
	material.scale_max = 3.6
	material.color = Color(0.71, 0.81, 0.46, 0.9)
	particles.process_material = material

	get_parent().add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free, CONNECT_ONE_SHOT)


func _build_crawler_texture() -> Texture2D:
	var image := Image.create(30, 22, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var shell_dark := Color(0.25, 0.30, 0.13, 1.0)
	var shell_mid := Color(0.39, 0.48, 0.18, 1.0)
	var shell_light := Color(0.71, 0.80, 0.29, 1.0)
	var acid_glow := Color(0.94, 1.0, 0.60, 1.0)

	for y in range(7, 16):
		for x in range(6, 24):
			image.set_pixel(x, y, shell_mid)
	for y in range(8, 14):
		for x in range(9, 21):
			image.set_pixel(x, y, shell_light)
	for y in range(3, 8):
		for x in range(18, 28):
			image.set_pixel(x, y, shell_dark)
	for y in range(16, 20):
		for x in range(7, 11):
			image.set_pixel(x, y, shell_dark)
		for x in range(19, 23):
			image.set_pixel(x, y, shell_dark)
	for y in range(2, 6):
		for x in range(24, 28):
			image.set_pixel(x, y, acid_glow)
	image.set_pixel(21, 6, acid_glow)
	image.set_pixel(21, 9, acid_glow)

	return ImageTexture.create_from_image(image)


func _setup_health_bar() -> void:
	if enemy_health_bar == null:
		return
	enemy_health_bar.min_value = 0.0
	enemy_health_bar.max_value = float(_max_health)
	enemy_health_bar.value = float(health)
	enemy_health_bar.show_percentage = false
	enemy_health_bar.visible = false

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.09, 0.09, 0.08, 0.88)
	background.corner_radius_top_left = 2
	background.corner_radius_top_right = 2
	background.corner_radius_bottom_left = 2
	background.corner_radius_bottom_right = 2
	enemy_health_bar.add_theme_stylebox_override("background", background)
	enemy_health_bar.add_theme_stylebox_override("fill", _build_health_bar_fill_style(1.0))


func _show_health_bar_from_combat() -> void:
	if enemy_health_bar == null:
		return
	enemy_health_bar.visible = sprite.visible
	_health_bar_hide_timer = HEALTH_BAR_HIDE_DELAY


func _refresh_health_bar() -> void:
	if enemy_health_bar == null:
		return
	var ratio := clampf(float(maxi(health, 0)) / float(maxi(_max_health, 1)), 0.0, 1.0)
	enemy_health_bar.max_value = float(_max_health)
	enemy_health_bar.value = float(maxi(health, 0))
	enemy_health_bar.add_theme_stylebox_override("fill", _build_health_bar_fill_style(ratio))


func _update_health_bar_visibility(delta: float) -> void:
	if enemy_health_bar == null or not enemy_health_bar.visible:
		return
	if not sprite.visible:
		enemy_health_bar.visible = false
		return
	_health_bar_hide_timer = maxf(0.0, _health_bar_hide_timer - delta)
	if _health_bar_hide_timer <= 0.0:
		enemy_health_bar.visible = false


func _build_health_bar_fill_style(health_ratio: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.91, 0.24, 0.18, 1.0).lerp(Color(0.66, 0.88, 0.25, 1.0), health_ratio)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style
