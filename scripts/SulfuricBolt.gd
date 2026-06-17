class_name SulfuricBolt
extends Projectile

const ACID_PUDDLE_SCENE := preload("res://scenes/AcidPuddle.tscn")
const SPEED := 350.0
const SPLASH_RADIUS := 24.0

@export var splash_radius: float = SPLASH_RADIUS

@onready var trail: GPUParticles2D = $Trail


func _ready() -> void:
	super._ready()
	damage_type = "chemical"
	damage = 22.0
	pierce = false
	_apply_sulfuric_bolt_visual()
	_setup_trail()


func _on_body_entered(body: Node) -> void:
	var hit_position := global_position
	var hit_target := body
	var hit_target_damage := _calculate_damage_for_body(hit_target, damage, damage_type, hit_position)
	if hit_target_damage > 0:
		_apply_resolved_damage_to_body(hit_target, hit_target_damage, damage_type, hit_position)

	_apply_splash_damage(hit_position, hit_target)
	_spawn_acid_puddle(hit_position)
	queue_free()


func _apply_splash_damage(hit_position: Vector2, primary_target: Node) -> void:
	var world := get_world_2d()
	if world == null:
		return

	var circle := CircleShape2D.new()
	circle.radius = splash_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, hit_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = collision_mask

	var hits := world.direct_space_state.intersect_shape(query, 32)
	var primary_id := primary_target.get_instance_id() if primary_target != null else -1
	var damaged_ids: Dictionary = {}
	for hit in hits:
		var body: Node = hit.get("collider")
		if body == null:
			continue
		var body_id: int = body.get_instance_id()
		if body_id == primary_id or damaged_ids.has(body_id):
			continue
		damaged_ids[body_id] = true
		var splash_damage := _calculate_damage_for_body(body, damage, damage_type, hit_position)
		if splash_damage <= 0:
			continue
		_apply_resolved_damage_to_body(body, splash_damage, damage_type, hit_position)


func _spawn_acid_puddle(hit_position: Vector2) -> void:
	if ACID_PUDDLE_SCENE == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var puddle := ACID_PUDDLE_SCENE.instantiate()
	if puddle is Node2D:
		(puddle as Node2D).global_position = hit_position
	parent.call_deferred("add_child", puddle)


func _setup_trail() -> void:
	if trail == null:
		return

	trail.emitting = true
	trail.amount = 12
	trail.lifetime = 0.28
	trail.explosiveness = 0.0
	trail.randomness = 0.45
	trail.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 2.0
	mat.color = Color(0.78, 0.95, 0.28, 1.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.98, 1.0, 0.48, 1.0))
	gradient.set_color(1, Color(0.36, 0.66, 0.10, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	mat.color_ramp = grad_tex
	mat.direction = Vector3(0.0, 0.0, 0.0)
	mat.spread = 42.0
	mat.initial_velocity_min = 14.0
	mat.initial_velocity_max = 36.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 2.0
	mat.scale_max = 4.5
	trail.process_material = mat


func _apply_sulfuric_bolt_visual() -> void:
	if sprite == null:
		return

	var image := Image.create(14, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var acid_dark := Color(0.34, 0.48, 0.06, 1.0)
	var acid_mid := Color(0.70, 0.86, 0.18, 1.0)
	var acid_light := Color(0.95, 1.0, 0.56, 1.0)
	for y in range(2, 4):
		for x in range(1, 10):
			image.set_pixel(x, y, acid_mid)
	for x in range(10, 14):
		image.set_pixel(x, 2, acid_light)
		image.set_pixel(x, 3, acid_light)
	for y in range(1, 5):
		image.set_pixel(0, y, acid_dark)
		image.set_pixel(1, y, acid_dark)
	sprite.texture = ImageTexture.create_from_image(image)


static func spawn(parent: Node, origin: Vector2, target_pos: Vector2) -> SulfuricBolt:
	var scene: PackedScene = load("res://scenes/SulfuricBolt.tscn")
	if scene == null:
		push_error("SulfuricBolt: res://scenes/SulfuricBolt.tscn not found")
		return null
	var bolt := scene.instantiate() as SulfuricBolt
	parent.add_child(bolt)
	bolt.global_position = origin
	bolt.velocity = origin.direction_to(target_pos) * SPEED
	bolt.rotation = bolt.velocity.angle()
	return bolt
