class_name RustBolt
extends Projectile

## RustBolt
## Oxidation-type projectile fired toward mouse cursor at 400px/s.
## Carries a GPUParticles2D rust-coloured trail.

const SPEED := 400.0

@onready var trail: GPUParticles2D = $Trail

var _visual_ready := false
var _trail_ready := false

func _ready() -> void:
	super._ready()
	damage_type = "oxidation"
	damage = 15.0
	pierce = false
	if not _visual_ready:
		_apply_rust_bolt_visual()
		_visual_ready = true
	if not _trail_ready:
		_setup_trail()
		_trail_ready = true
	if trail != null:
		trail.restart()
		trail.emitting = true


func _pool_reset() -> void:
	super._pool_reset()
	damage_type = "oxidation"
	damage = 15.0
	if trail != null:
		trail.emitting = false

func _setup_trail() -> void:
	if trail == null:
		return

	trail.emitting = true
	trail.amount = 8
	trail.lifetime = 0.2
	trail.explosiveness = 0.0
	trail.randomness = 0.4
	trail.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 2.0
	# Rust orange base colour → fades to transparent
	mat.color = Color(0.85, 0.35, 0.05, 1.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.85, 0.35, 0.05, 1.0))
	gradient.set_color(1, Color(0.5, 0.15, 0.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	mat.color_ramp = grad_tex
	mat.direction = Vector3(0.0, 0.0, 0.0)
	mat.spread = 30.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 30.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 2.0
	mat.scale_max = 4.0
	trail.process_material = mat


func _apply_rust_bolt_visual() -> void:
	if sprite == null:
		return

	var image := Image.create(14, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rust_dark := Color(0.46, 0.18, 0.08, 1.0)
	var rust_mid := Color(0.74, 0.31, 0.11, 1.0)
	var rust_light := Color(0.91, 0.53, 0.18, 1.0)
	for y in range(2, 4):
		for x in range(1, 10):
			image.set_pixel(x, y, rust_mid)
	for x in range(10, 14):
		image.set_pixel(x, 2, rust_light)
		image.set_pixel(x, 3, rust_light)
	for y in range(1, 5):
		image.set_pixel(0, y, rust_dark)
		image.set_pixel(1, y, rust_dark)
	sprite.texture = ImageTexture.create_from_image(image)


static func spawn(parent: Node, origin: Vector2, target_pos: Vector2) -> RustBolt:
	var bolt := ObjectPool.get_instance_by_id(ObjectPool.SCENE_RUST_BOLT) as RustBolt
	if bolt == null:
		return null
	parent.add_child(bolt)
	bolt.global_position = origin
	bolt.velocity = origin.direction_to(target_pos) * SPEED
	bolt.rotation = bolt.velocity.angle()
	return bolt
