class_name ShrapnelProjectile
extends Area2D

const SPEED := 260.0
const DAMAGE := 8.0
const DAMAGE_TYPE := "physical_sharp"
const LIFETIME_SECONDS := 0.55

@export var velocity: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D

var _lifetime_timer: Timer = null
var _visual_ready := false

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not _visual_ready:
		_apply_visual()
		_visual_ready = true
	_ensure_lifetime_timer()
	_lifetime_timer.start(LIFETIME_SECONDS)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D) or body.name != "Player":
		return

	var resolved_damage := int(DamageCalculator.calculate(DAMAGE, DAMAGE_TYPE, body, global_position))
	if resolved_damage <= 0:
		ObjectPool.release(self)
		return

	var health_system := body.get_node_or_null("HealthSystem")
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(resolved_damage, StringName(DAMAGE_TYPE), "Shrapnel burst")
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(resolved_damage, StringName(DAMAGE_TYPE), "Shrapnel burst")

	ObjectPool.release(self)


func _pool_reset() -> void:
	velocity = Vector2.ZERO
	rotation = 0.0
	monitoring = true
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
	var projectile := ObjectPool.get_instance_by_id(ObjectPool.SCENE_SHRAPNEL_PROJECTILE) as Area2D
	if projectile == null:
		return null
	parent.add_child(projectile)
	projectile.global_position = origin
	projectile.set("velocity", direction.normalized() * SPEED)
	projectile.rotation = direction.angle()
	return projectile
