class_name Projectile
extends Area2D

## Projectile
## Velocity-driven projectile that resolves damage through DamageCalculator on enemy hit.

@export var velocity: Vector2 = Vector2.ZERO
@export var damage: float = 10.0
@export var damage_type: String = "physical_sharp"
@export var pierce: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_ensure_default_visual()
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += velocity * delta
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"enemy"):
		return

	var final_damage := DamageCalculator.calculate(damage, damage_type, body, global_position)
	var resolved_damage := int(final_damage)
	if resolved_damage <= 0:
		if not pierce:
			queue_free()
		return

	var health_system := body.get_node_or_null("HealthSystem")
	if health_system == null:
		health_system = body.find_child("HealthSystem", true, false)
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(resolved_damage, StringName(damage_type))
	elif body.has_method("take_resolved_damage"):
		body.take_resolved_damage(resolved_damage, damage_type, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(resolved_damage, damage_type, global_position)
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(resolved_damage, StringName(damage_type))

	if not pierce:
		queue_free()


func _ensure_default_visual() -> void:
	if sprite == null or sprite.texture != null:
		return

	var image := Image.create(12, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(1, 3):
		for x in range(1, 10):
			image.set_pixel(x, y, Color(0.82, 0.80, 0.74, 1.0))
	for x in range(9, 12):
		image.set_pixel(x, 1, Color(0.94, 0.90, 0.72, 1.0))
		image.set_pixel(x, 2, Color(0.94, 0.90, 0.72, 1.0))
	sprite.texture = ImageTexture.create_from_image(image)
