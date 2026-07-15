extends Area2D

const BURN_DAMAGE_PER_SECOND := 5
const BURN_DURATION_SECONDS := 4.0
const PATCH_LIFETIME_SECONDS := 1.5

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var particles: GPUParticles2D = $GPUParticles2D

var _lifetime_timer: Timer = null
var _particles_configured := false

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not _particles_configured:
		_configure_particles()
		_particles_configured = true
	particles.restart()
	particles.emitting = true
	_ensure_lifetime_timer()
	_lifetime_timer.start(PATCH_LIFETIME_SECONDS)


func _pool_reset() -> void:
	monitoring = true
	remove_meta(&"tile_coords")
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
	if not (body is CharacterBody2D) or body.name != "Player":
		return

	var health_system := body.get_node_or_null("HealthSystem")
	if health_system != null and health_system.has_method("add_status_effect"):
		health_system.add_status_effect(&"burning", BURN_DAMAGE_PER_SECOND, BURN_DURATION_SECONDS, "Sulfur flame patch")


func _configure_particles() -> void:
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 18.0
	process_material.initial_velocity_min = 8.0
	process_material.initial_velocity_max = 18.0
	process_material.gravity = Vector3(0.0, -12.0, 0.0)
	process_material.scale_min = 0.4
	process_material.scale_max = 0.9
	process_material.color = Color(1.0, 0.57, 0.18, 0.9)
	process_material.color_ramp = _build_flame_gradient()
	particles.process_material = process_material
	particles.texture = _build_flame_texture()
	particles.amount = 12
	particles.lifetime = PATCH_LIFETIME_SECONDS
	particles.one_shot = true
	particles.explosiveness = 0.0
	particles.local_coords = false


func _build_flame_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.82, 0.32, 0.0))
	gradient.add_point(0.2, Color(1.0, 0.72, 0.24, 0.95))
	gradient.add_point(0.7, Color(0.96, 0.33, 0.08, 0.7))
	gradient.add_point(1.0, Color(0.28, 0.06, 0.02, 0.0))

	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_flame_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(8):
		for x in range(8):
			var dx := float(x - 3.5) / 3.5
			var dy := float(y - 5.0) / 5.0
			var falloff := 1.0 - clampf(dx * dx + dy * dy, 0.0, 1.0)
			if falloff <= 0.0:
				continue
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff))
	return ImageTexture.create_from_image(image)
