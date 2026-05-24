extends Node2D

const IRON_GOLEM_SCENE := preload("res://scenes/IronGolem.tscn")
const RESPAWN_SECONDS := 300.0
const SPAWN_EFFECT_LIFETIME := 0.45

@export var spawn_position: Array[Vector2] = []

var _active_golems: Dictionary = {}
var _respawn_timers: Dictionary = {}


func _ready() -> void:
	for index: int in spawn_position.size():
		_ensure_respawn_timer(index)
		_spawn_golem(index)


func _spawn_golem(index: int) -> void:
	if index < 0 or index >= spawn_position.size():
		return
	if _active_golems.has(index):
		var existing_golem: Node = _active_golems[index]
		if is_instance_valid(existing_golem):
			return

	var golem := IRON_GOLEM_SCENE.instantiate()
	golem.global_position = spawn_position[index]
	add_child(golem)
	_active_golems[index] = golem

	var died_callable := Callable(self, "_on_golem_died").bind(index)
	if not golem.died.is_connected(died_callable):
		golem.died.connect(died_callable, CONNECT_ONE_SHOT)

	_play_spawn_effect(spawn_position[index])


func _ensure_respawn_timer(index: int) -> Timer:
	if _respawn_timers.has(index):
		return _respawn_timers[index] as Timer

	var timer := Timer.new()
	timer.name = "RespawnTimer%d" % index
	timer.wait_time = RESPAWN_SECONDS
	timer.one_shot = true
	timer.timeout.connect(_on_respawn_timeout.bind(index))
	add_child(timer)
	_respawn_timers[index] = timer
	return timer


func _on_golem_died(_golem: CharacterBody2D, index: int) -> void:
	_active_golems.erase(index)
	var timer := _ensure_respawn_timer(index)
	timer.start()


func _on_respawn_timeout(index: int) -> void:
	_spawn_golem(index)


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
