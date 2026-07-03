extends Node2D

const IRON_GOLEM_SCENE := preload("res://scenes/IronGolem.tscn")
const DAY_RESPAWN_SECONDS := 300.0
const NIGHT_RESPAWN_SECONDS := 180.0
const SPAWN_EFFECT_LIFETIME := 0.45

@export var enemy_scene: PackedScene = IRON_GOLEM_SCENE
@export var spawn_position: Array[Vector2] = []
@export_range(1, 8, 1) var spawn_group_size := 1
@export var spawn_group_radius := 18.0
@export var requires_post_tutorial_loop := false

var _active_enemies: Dictionary = {}
var _respawn_timers: Dictionary = {}


func _ready() -> void:
	if requires_post_tutorial_loop and not _is_post_tutorial_loop_active():
		if ResearchObjectives != null and ResearchObjectives.has_signal("objective_completed"):
			var objective_callable := Callable(self, "_on_objective_completed")
			if not ResearchObjectives.objective_completed.is_connected(objective_callable):
				ResearchObjectives.objective_completed.connect(objective_callable)
		return
	for index: int in spawn_position.size():
		_ensure_respawn_timer(index)
		_spawn_enemy_group(index)


func _spawn_enemy_group(index: int) -> void:
	if index < 0 or index >= spawn_position.size():
		return
	if enemy_scene == null:
		return
	if _active_enemies.has(index):
		var active_group: Array = _active_enemies[index]
		if _has_living_enemy(active_group):
			return

	var active_group: Array[Node] = []
	for group_index in range(spawn_group_size):
		var enemy := enemy_scene.instantiate()
		if enemy is Node2D:
			(enemy as Node2D).position = to_local(spawn_position[index] + _get_group_offset(group_index))
		add_child(enemy)
		active_group.append(enemy)

		var died_callable := Callable(self, "_on_enemy_died").bind(index)
		if enemy.has_signal("died") and not enemy.died.is_connected(died_callable):
			enemy.died.connect(died_callable, CONNECT_ONE_SHOT)

	_active_enemies[index] = active_group
	_play_spawn_effect(spawn_position[index])


func _has_living_enemy(active_group: Array) -> bool:
	for enemy in active_group:
		if enemy != null and is_instance_valid(enemy):
			return true
	return false


func _get_group_offset(group_index: int) -> Vector2:
	if spawn_group_size <= 1:
		return Vector2.ZERO
	var angle := (TAU / float(spawn_group_size)) * float(group_index)
	return Vector2(cos(angle), sin(angle)) * spawn_group_radius


func _ensure_respawn_timer(index: int) -> Timer:
	if _respawn_timers.has(index):
		return _respawn_timers[index] as Timer

	var timer := Timer.new()
	timer.name = "RespawnTimer%d" % index
	timer.one_shot = true
	timer.timeout.connect(_on_respawn_timeout.bind(index))
	add_child(timer)
	_respawn_timers[index] = timer
	return timer


func _on_enemy_died(_enemy: CharacterBody2D, index: int) -> void:
	var active_group: Array = _active_enemies.get(index, [])
	var remaining_group: Array[Node] = []
	for enemy in active_group:
		if enemy == _enemy or enemy == null or not is_instance_valid(enemy):
			continue
		remaining_group.append(enemy)
	if _has_living_enemy(remaining_group):
		_active_enemies[index] = remaining_group
		return
	_active_enemies.erase(index)
	var timer := _ensure_respawn_timer(index)
	
	var wait_time := DAY_RESPAWN_SECONDS
	if GameManager.has_method("is_night") and GameManager.is_night():
		wait_time = NIGHT_RESPAWN_SECONDS
		
	timer.wait_time = wait_time
	timer.start()


func _on_respawn_timeout(index: int) -> void:
	if requires_post_tutorial_loop and not _is_post_tutorial_loop_active():
		return
	_spawn_enemy_group(index)


func _on_objective_completed(_objective_id: StringName) -> void:
	if not _is_post_tutorial_loop_active():
		return
	for index: int in spawn_position.size():
		_ensure_respawn_timer(index)
		_spawn_enemy_group(index)


func _is_post_tutorial_loop_active() -> bool:
	return GameManager != null and GameManager.post_tutorial_loop_active


func _play_spawn_effect(effect_position: Vector2) -> void:
	var particles := CPUParticles2D.new()
	particles.position = to_local(effect_position)
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 18
	particles.lifetime = 0.35
	particles.explosiveness = 1.0
	particles.spread = 50.0
	particles.initial_velocity_min = 35.0
	particles.initial_velocity_max = 85.0
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 1.7
	particles.gravity = Vector2(0.0, 110.0)
	particles.direction = Vector2.UP
	particles.color = Color(0.83, 0.73, 0.52, 1.0)
	add_child(particles)
	particles.emitting = true

	var cleanup_timer := get_tree().create_timer(SPAWN_EFFECT_LIFETIME)
	cleanup_timer.timeout.connect(particles.queue_free, CONNECT_ONE_SHOT)
