extends Area2D

const CLOUD_RADIUS := 64.0
const DAMAGE_PER_SECOND := 6
const STATUS_DURATION_SECONDS := 10.0
const CLOUD_DURATION_SECONDS := 10.0
const DAMAGE_TICK_SECONDS := 1.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var damage_timer: Timer = $DamageTimer
@onready var particles: GPUParticles2D = $GPUParticles2D

var _tracked_bodies: Dictionary[int, Node] = {}
var _lifetime_timer: Timer = null
var _cloud_configured := false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	damage_timer.wait_time = DAMAGE_TICK_SECONDS
	if not damage_timer.timeout.is_connected(_on_damage_timer_timeout):
		damage_timer.timeout.connect(_on_damage_timer_timeout)
	if not _cloud_configured:
		_configure_cloud()
		_cloud_configured = true
	particles.restart()
	particles.emitting = true
	_ensure_lifetime_timer()
	_lifetime_timer.start(CLOUD_DURATION_SECONDS)


func _pool_reset() -> void:
	_tracked_bodies.clear()
	monitoring = true
	if damage_timer != null:
		damage_timer.stop()
	if particles != null:
		particles.emitting = false
	if _lifetime_timer != null:
		_lifetime_timer.stop()


func _ensure_lifetime_timer() -> void:
	if _lifetime_timer != null:
		return
	_lifetime_timer = Timer.new()
	_lifetime_timer.one_shot = true
	_lifetime_timer.timeout.connect(_release_to_pool)
	add_child(_lifetime_timer)


func _release_to_pool() -> void:
	ObjectPool.release(self)


func _on_body_entered(body: Node) -> void:
	if not _can_affect_body(body):
		return
	_tracked_bodies[body.get_instance_id()] = body
	_apply_toxic_effect(body)
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
		_apply_toxic_effect(body)

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
		health_system.take_resolved_damage(DAMAGE_PER_SECOND, &"toxic", "Toxic cloud")
	elif health_system.has_method("take_damage"):
		health_system.take_damage(DAMAGE_PER_SECOND, &"toxic", "Toxic cloud")


func _apply_toxic_effect(body: Node) -> void:
	var health_system := _get_health_system(body)
	if health_system != null and health_system.has_method("add_status_effect"):
		health_system.add_status_effect(&"toxic", 0, STATUS_DURATION_SECONDS, "Toxic cloud")


func _can_affect_body(body: Node) -> bool:
	return _get_health_system(body) != null


func _get_health_system(body: Node) -> Node:
	if body == null:
		return null
	var health_system := body.get_node_or_null("HealthSystem")
	if health_system == null:
		health_system = body.find_child("HealthSystem", true, false)
	return health_system


func _configure_cloud() -> void:
	var shape := collision_shape.shape as CircleShape2D
	if shape != null:
		shape.radius = CLOUD_RADIUS

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 28.0
	process_material.initial_velocity_min = 4.0
	process_material.initial_velocity_max = 12.0
	process_material.gravity = Vector3(0.0, -3.0, 0.0)
	process_material.scale_min = 0.9
	process_material.scale_max = 1.8
	process_material.color = Color(0.42, 0.90, 0.35, 0.42)
	process_material.color_ramp = _build_cloud_gradient()
	particles.process_material = process_material
	particles.texture = _build_cloud_texture()
	particles.amount = 28
	particles.lifetime = 2.4
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.local_coords = false
	particles.visibility_rect = Rect2(Vector2(-72.0, -72.0), Vector2(144.0, 144.0))


func _build_cloud_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.82, 1.0, 0.58, 0.0))
	gradient.add_point(0.2, Color(0.62, 0.96, 0.36, 0.55))
	gradient.add_point(1.0, Color(0.18, 0.42, 0.12, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_cloud_texture() -> Texture2D:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(12):
		for x in range(12):
			var distance := Vector2(float(x), float(y)).distance_to(Vector2(5.5, 5.5))
			var alpha := clampf(1.0 - distance / 5.8, 0.0, 1.0)
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
