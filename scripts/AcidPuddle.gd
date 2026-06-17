extends Area2D

const PUDDLE_DURATION_SECONDS := 8.0
const DAMAGE_PER_SECOND := 4
const DAMAGE_TICK_SECONDS := 1.0
const PUDDLE_SIZE := Vector2(8.0, 8.0)

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var damage_timer: Timer = $DamageTimer
@onready var puddle_visual: ColorRect = $ColorRect

var _tracked_bodies: Dictionary[int, Node] = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	damage_timer.wait_time = DAMAGE_TICK_SECONDS
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	_configure_visual()
	get_tree().create_timer(PUDDLE_DURATION_SECONDS).timeout.connect(queue_free, CONNECT_ONE_SHOT)


func _on_body_entered(body: Node) -> void:
	if not _can_damage_body(body):
		return
	_tracked_bodies[body.get_instance_id()] = body
	_update_damage_timer()


func _on_body_exited(body: Node) -> void:
	_tracked_bodies.erase(body.get_instance_id())
	_update_damage_timer()


func _on_damage_timer_timeout() -> void:
	if _tracked_bodies.is_empty():
		damage_timer.stop()
		return

	var stale_ids: Array[int] = []
	for body_id: int in _tracked_bodies.keys():
		var body: Node = _tracked_bodies[body_id]
		if body == null or not is_instance_valid(body):
			stale_ids.append(body_id)
			continue
		_apply_damage_to_body(body)

	for body_id in stale_ids:
		_tracked_bodies.erase(body_id)

	_update_damage_timer()


func _update_damage_timer() -> void:
	if _tracked_bodies.is_empty():
		damage_timer.stop()
		return
	if damage_timer.is_stopped():
		damage_timer.start()


func _apply_damage_to_body(body: Node) -> void:
	var health_system := _get_health_system(body)
	if health_system == null:
		return
	if health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(DAMAGE_PER_SECOND, &"chemical", "Acid puddle")
	elif health_system.has_method("take_damage"):
		health_system.take_damage(DAMAGE_PER_SECOND, &"chemical", "Acid puddle")


func _can_damage_body(body: Node) -> bool:
	return _get_health_system(body) != null


func _get_health_system(body: Node) -> Node:
	if body == null:
		return null
	var health_system := body.get_node_or_null("HealthSystem")
	if health_system == null:
		health_system = body.find_child("HealthSystem", true, false)
	return health_system


func _configure_visual() -> void:
	puddle_visual.color = Color(0.48, 0.82, 0.20, 0.55)
	puddle_visual.position = -PUDDLE_SIZE * 0.5
	puddle_visual.size = PUDDLE_SIZE
	var shape := collision_shape.shape as CircleShape2D
	if shape != null:
		shape.radius = 4.0
