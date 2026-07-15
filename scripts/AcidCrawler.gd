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
const DEFAULT_CONFIG: EnemyConfig = preload("res://data/config/acid_crawler_config.tres")

@export var config: EnemyConfig = DEFAULT_CONFIG

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var enemy_health_bar: ProgressBar = $EnemyHealthBar
@onready var scan_proxy: Area2D = $ScanProxy
@onready var scan_proxy_shape: CollisionShape2D = $ScanProxy/CollisionShape2D
@onready var emerge_warning_particles: GPUParticles2D = $EmergeWarningParticles
@onready var death_particles: GPUParticles2D = $DeathParticles

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
var health := 0
var resistances: Dictionary = {}
var _health_bar_hide_timer := 0.0
var _subsurface_signal := false
var _night_active := false
var _patrol_speed := 0.0
var _burrow_speed := 0.0
var _returning_to_spawn := false


func _ready() -> void:
	add_to_group(&"enemy")
	if config == null:
		config = DEFAULT_CONFIG
	health = config.health
	resistances = config.resistances.duplicate(true)
	_max_health = config.health
	spawn_position = global_position
	target_position = global_position
	_patrol_target = global_position
	_burrow_target_position = global_position
	sprite.texture = _build_crawler_texture()
	navigation_agent.path_desired_distance = 3.0
	navigation_agent.target_desired_distance = 6.0
	_setup_health_bar()
	_sync_scan_proxy()
	_sync_player_collision_exception()

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
	_unregister_from_base_defense()
	velocity = Vector2.ZERO
	_set_surface_visible(true)
	_sync_scan_proxy()
	enemy_health_bar.visible = false
	died.emit(self)
	_drop_limestone()
	_spawn_death_particles()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color(0.44, 0.48, 0.42, 0.88), 1.5)
	tween.tween_property(sprite, "scale", Vector2(1.3, 0.35), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(1.5).timeout
	queue_free()


func _exit_tree() -> void:
	_unregister_from_base_defense()


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
	var effective_detection_radius := _get_effective_detection_radius()
	if effective_detection_radius <= 0.0:
		_report_lit_zone_presence()
		return
	var attraction_target := _get_base_attraction_target()
	if attraction_target != Vector2(INF, INF):
		_patrol_target = attraction_target
		if global_position.distance_to(attraction_target) <= 18.0:
			_report_base_breach()
		_face_target(_patrol_target)
		velocity = global_position.direction_to(_patrol_target) * _patrol_speed
		return
	if _player_target != null and global_position.distance_to(_player_target.global_position) <= effective_detection_radius:
		_report_lit_zone_presence()
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
	elif _player_target != null and _player_target.global_position.distance_to(spawn_position) <= config.max_pursuit_radius:
		_burrow_target_position = _get_player_emerge_position()
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
	if _get_effective_detection_radius() <= 0.0:
		_report_lit_zone_presence()
		_begin_burrow(spawn_position, true)
		return
	if distance_to_player > config.reburrow_radius:
		_begin_burrow(spawn_position, true)
		return
	if global_position.distance_to(spawn_position) > config.max_pursuit_radius:
		_begin_burrow(spawn_position, true)
		return
	if _player_target.global_position.distance_to(spawn_position) > config.max_pursuit_radius:
		_begin_burrow(spawn_position, true)
		return

	_face_target(_player_target.global_position)
	if distance_to_player < config.min_attack_separation:
		var separation_direction := _player_target.global_position.direction_to(global_position)
		if separation_direction == Vector2.ZERO:
			separation_direction = Vector2.UP
		velocity = separation_direction * (_patrol_speed * 0.75)
		return
	if distance_to_player > config.attack_range:
		velocity = global_position.direction_to(_player_target.global_position) * (_patrol_speed + 12.0)
		return

	velocity = Vector2.ZERO
	if _attack_cooldown_timer <= 0.0:
		_fire_acid_spit()
		_attack_cooldown_timer = config.attack_cooldown_seconds


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
	_emerge_warning_timer = config.emerge_warning_seconds
	_subsurface_signal = true
	_set_surface_visible(false)
	_sync_scan_proxy()
	_spawn_emerge_warning_fx(_burrow_target_position)
	var camera_shake := EventBus.get_camera_shake()
	if camera_shake != null and camera_shake.has_method("shake"):
		camera_shake.shake(0.25, 0.4)


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
	var offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(20.0, config.patrol_radius)
	_patrol_target = spawn_position + offset


func _fire_acid_spit() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var target := _player_target.global_position if _player_target != null else global_position + Vector2.RIGHT * config.attack_range
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
	_sync_player_collision_exception()


func _find_player() -> CharacterBody2D:
	var player := GameManager.get_player()
	if player is CharacterBody2D:
		return player as CharacterBody2D
	return null


func _sync_player_collision_exception() -> void:
	if _player_target == null or not is_instance_valid(_player_target):
		return
	add_collision_exception_with(_player_target)
	_player_target.add_collision_exception_with(self)


func _get_effective_detection_radius() -> float:
	if not _night_active or EventBus.get_base_defense_system() == null or not EventBus.get_base_defense_system().has_method("get_detection_multiplier_at"):
		return config.detection_radius
	return config.detection_radius * float(EventBus.get_base_defense_system().get_detection_multiplier_at(global_position))


func _report_lit_zone_presence() -> void:
	if not _night_active or EventBus.get_base_defense_system() == null or not EventBus.get_base_defense_system().has_method("is_position_in_powered_light"):
		return
	if not EventBus.get_base_defense_system().is_position_in_powered_light(global_position):
		return
	EventBus.get_base_defense_system().report_night_threat(get_instance_id(), global_position)
	_report_base_breach()


func _get_base_attraction_target() -> Vector2:
	if not _night_active or EventBus.get_base_threat_director() == null:
		return Vector2(INF, INF)
	if not EventBus.get_base_threat_director().has_method("get_enemy_attraction_target"):
		return Vector2(INF, INF)
	return EventBus.get_base_threat_director().get_enemy_attraction_target(global_position)


func _report_base_breach() -> void:
	if not _night_active or EventBus.get_base_threat_director() == null:
		return
	if EventBus.get_base_threat_director().has_method("report_enemy_base_breach"):
		EventBus.get_base_threat_director().report_enemy_base_breach(self)


func _unregister_from_base_defense() -> void:
	if EventBus.get_base_defense_system() != null and EventBus.get_base_defense_system().has_method("unregister_enemy"):
		EventBus.get_base_defense_system().unregister_enemy(get_instance_id())


func _get_player_tile_center() -> Vector2:
	if _player_target == null:
		return spawn_position
	var ground := get_tree().current_scene.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return _player_target.global_position
	var local_position := ground.to_local(_player_target.global_position)
	var coords := ground.local_to_map(local_position)
	return ground.to_global(ground.map_to_local(coords))


func _get_player_emerge_position() -> Vector2:
	var player_center := _get_player_tile_center()
	if _player_target == null:
		return player_center
	var approach_direction := global_position - player_center
	if approach_direction.length_squared() <= 0.001:
		approach_direction = spawn_position - player_center
	if approach_direction.length_squared() <= 0.001:
		approach_direction = Vector2.DOWN
	return player_center + approach_direction.normalized() * config.player_emerge_offset


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
	_patrol_speed = config.move_speed
	_burrow_speed = config.burrow_speed
	if current_state == State.DEAD:
		return
	if current_state == State.IDLE:
		current_state = State.PATROL
		_set_surface_visible(true)
		_choose_patrol_target()


func _on_night_started() -> void:
	_night_active = true
	_patrol_speed = config.night_move_speed
	_burrow_speed = config.night_burrow_speed
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
	if emerge_warning_particles == null:
		return
	emerge_warning_particles.global_position = world_position
	emerge_warning_particles.restart()
	emerge_warning_particles.emitting = true


func _spawn_death_particles() -> void:
	if death_particles == null:
		return
	death_particles.global_position = global_position
	death_particles.restart()
	death_particles.emitting = true


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
	_refresh_health_bar()


func _show_health_bar_from_combat() -> void:
	if enemy_health_bar == null:
		return
	enemy_health_bar.visible = sprite.visible
	_health_bar_hide_timer = config.health_bar_hide_delay


func _refresh_health_bar() -> void:
	if enemy_health_bar == null:
		return
	var ratio := clampf(float(maxi(health, 0)) / float(maxi(_max_health, 1)), 0.0, 1.0)
	enemy_health_bar.max_value = float(_max_health)
	enemy_health_bar.value = float(maxi(health, 0))
	var fill_style := enemy_health_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = Color(0.91, 0.24, 0.18, 1.0).lerp(Color(0.66, 0.88, 0.25, 1.0), ratio)


func _update_health_bar_visibility(delta: float) -> void:
	if enemy_health_bar == null or not enemy_health_bar.visible:
		return
	if not sprite.visible:
		enemy_health_bar.visible = false
		return
	_health_bar_hide_timer = maxf(0.0, _health_bar_hide_timer - delta)
	if _health_bar_hide_timer <= 0.0:
		enemy_health_bar.visible = false
