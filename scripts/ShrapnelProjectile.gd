class_name ShrapnelProjectile
extends Area2D

const SPEED := 260.0
const DAMAGE := 8.0
const DAMAGE_TYPE := "physical_sharp"
const LIFETIME_SECONDS := 0.55

@export var velocity: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_visual()
	get_tree().create_timer(LIFETIME_SECONDS).timeout.connect(queue_free, CONNECT_ONE_SHOT)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D) or body.name != "Player":
		return

	var resolved_damage := int(DamageCalculator.calculate(DAMAGE, DAMAGE_TYPE, body, global_position))
	if resolved_damage <= 0:
		queue_free()
		return

	var health_system := body.get_node_or_null("HealthSystem")
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(resolved_damage, StringName(DAMAGE_TYPE), "Shrapnel burst")
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(resolved_damage, StringName(DAMAGE_TYPE), "Shrapnel burst")

	queue_free()


func _apply_visual() -> void:
	if sprite == null:
		return

	var image := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var shard_dark := Color(0.62, 0.64, 0.68, 1.0)
	var shard_light := Color(0.88, 0.90, 0.94, 1.0)
	for y in range(1, 3):
		for x in range(1, 6):
			image.set_pixel(x, y, shard_dark)
	for x in range(5, 8):
		image.set_pixel(x, 1, shard_light)
		image.set_pixel(x, 2, shard_light)
	sprite.texture = ImageTexture.create_from_image(image)


static func spawn(parent: Node, origin: Vector2, direction: Vector2) -> Node2D:
	var scene: PackedScene = load("res://scenes/ShrapnelProjectile.tscn")
	if scene == null:
		push_error("ShrapnelProjectile: res://scenes/ShrapnelProjectile.tscn not found")
		return null
	var projectile := scene.instantiate() as Area2D
	parent.add_child(projectile)
	projectile.global_position = origin
	projectile.set("velocity", direction.normalized() * SPEED)
	projectile.rotation = direction.angle()
	return projectile
