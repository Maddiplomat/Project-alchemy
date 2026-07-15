extends Node2D

const LIFETIME_SECONDS := 0.8

@export var damage_radius_pixels := 32.0
@export var damage_amount := 30
@export var damage_type := "chemical"
@export var destroy_inventory_slot := true

@onready var particles: GPUParticles2D = $GPUParticles2D

var _activated := false
var _lifetime_timer: Timer = null
var _particles_configured := false


func _ready() -> void:
	call_deferred("_activate_explosion")


func _activate_explosion() -> void:
	if _activated:
		return
	_activated = true
	_apply_explosion_damage()
	if destroy_inventory_slot:
		_destroy_random_inventory_slot()
	if not _particles_configured:
		_configure_particles()
		_particles_configured = true
	particles.restart()
	particles.emitting = true
	_ensure_lifetime_timer()
	_lifetime_timer.start(LIFETIME_SECONDS)


func _pool_reset() -> void:
	_activated = false
	damage_radius_pixels = 32.0
	damage_amount = 30
	damage_type = "chemical"
	destroy_inventory_slot = true
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


func _apply_explosion_damage() -> void:
	var world := get_world_2d()
	if world == null:
		return

	var circle := CircleShape2D.new()
	circle.radius = damage_radius_pixels
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1

	var hits := world.direct_space_state.intersect_shape(query, 32)
	var damaged_ids: Dictionary = {}
	for hit in hits:
		var body: Node = hit.get("collider")
		if body == null:
			continue
		var body_id: int = body.get_instance_id()
		if damaged_ids.has(body_id):
			continue
		damaged_ids[body_id] = true
		_apply_damage_to_body(body)


func _apply_damage_to_body(body: Node) -> void:
	var resolved_damage := int(DamageCalculator.calculate(float(damage_amount), damage_type, body, global_position))
	if resolved_damage <= 0:
		return

	var health_system := body.get_node_or_null("HealthSystem")
	if health_system == null:
		health_system = body.find_child("HealthSystem", true, false)
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(resolved_damage, StringName(damage_type), "Chemical explosion")
	elif body.has_method("take_resolved_damage"):
		body.take_resolved_damage(resolved_damage, damage_type, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(resolved_damage, damage_type, global_position)
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(resolved_damage, StringName(damage_type), "Chemical explosion")


func _destroy_random_inventory_slot() -> void:
	InventoryManager.destroy_random_occupied_slot()


func _configure_particles() -> void:
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 30.0
	process_material.initial_velocity_max = 85.0
	process_material.gravity = Vector3(0.0, 20.0, 0.0)
	process_material.scale_min = 0.5
	process_material.scale_max = 1.2
	process_material.color = Color(1.0, 0.76, 0.24, 1.0)
	process_material.color_ramp = _build_gradient()
	particles.process_material = process_material
	particles.texture = _build_particle_texture()
	particles.amount = 24
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false


func _build_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.94, 0.56, 0.0))
	gradient.add_point(0.18, Color(1.0, 0.80, 0.22, 0.95))
	gradient.add_point(0.7, Color(0.98, 0.34, 0.05, 0.65))
	gradient.add_point(1.0, Color(0.25, 0.06, 0.02, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_particle_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(8):
		for x in range(8):
			var distance := Vector2(float(x), float(y)).distance_to(Vector2(3.5, 3.5))
			var alpha := clampf(1.0 - distance / 3.8, 0.0, 1.0)
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
