class_name AcidSpit
extends Area2D

const MAX_TRAVEL_DISTANCE := 96.0
const ARC_HEIGHT := 20.0
const IMPACT_RADIUS := 10.0
const DAMAGE := 16

@export var travel_speed: float = 170.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: ColorRect = $Shadow

var _start_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _travel_distance := 0.0
var _travel_duration := 0.0
var _travel_elapsed := 0.0
var _travel_direction := Vector2.RIGHT
var _visual_ready := false


func _ready() -> void:
	if not _visual_ready:
		_build_visual()
		_visual_ready = true


func _physics_process(delta: float) -> void:
	if _travel_duration <= 0.0:
		_land()
		return

	_travel_elapsed = minf(_travel_elapsed + delta, _travel_duration)
	var progress := clampf(_travel_elapsed / _travel_duration, 0.0, 1.0)
	global_position = _start_position.lerp(_target_position, progress)

	var arc_offset := sin(progress * PI) * ARC_HEIGHT
	sprite.position.y = -arc_offset
	shadow.modulate.a = lerpf(0.18, 0.42, 1.0 - progress)

	if progress >= 1.0:
		_land()


func configure(origin: Vector2, target_position: Vector2) -> void:
	_start_position = origin
	var offset := target_position - origin
	if offset.length() <= 0.001:
		offset = Vector2.RIGHT
	_travel_distance = minf(offset.length(), MAX_TRAVEL_DISTANCE)
	_travel_direction = offset.normalized()
	_target_position = origin + _travel_direction * _travel_distance
	_travel_duration = _travel_distance / maxf(travel_speed, 1.0)
	_travel_elapsed = 0.0
	global_position = origin
	rotation = _travel_direction.angle()


static func spawn(parent: Node, origin: Vector2, target_position: Vector2) -> AcidSpit:
	var spit := ObjectPool.get_instance_by_id(ObjectPool.SCENE_ACID_SPIT) as AcidSpit
	if spit == null:
		return null
	parent.add_child(spit)
	spit.configure(origin, target_position)
	return spit


func _land() -> void:
	_apply_impact_damage()
	_spawn_acid_puddle()
	ObjectPool.release(self)


func _pool_reset() -> void:
	_start_position = Vector2.ZERO
	_target_position = Vector2.ZERO
	_travel_distance = 0.0
	_travel_duration = 0.0
	_travel_elapsed = 0.0
	_travel_direction = Vector2.RIGHT
	rotation = 0.0
	monitoring = true
	if sprite != null:
		sprite.position.y = 0.0
	if shadow != null:
		shadow.modulate.a = 0.26


func _apply_impact_damage() -> void:
	var world := get_world_2d()
	if world == null:
		return

	var circle := CircleShape2D.new()
	circle.radius = IMPACT_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1

	for hit in world.direct_space_state.intersect_shape(query, 8):
		var body := hit.get("collider") as Node
		if body == null or body.name != "Player":
			continue
		var health_system := body.get_node_or_null("HealthSystem")
		if health_system != null and health_system.has_method("take_resolved_damage"):
			health_system.take_resolved_damage(DAMAGE, &"chemical", "Acid spit")
		elif health_system != null and health_system.has_method("take_damage"):
			health_system.take_damage(DAMAGE, &"chemical", "Acid spit")
		elif body.has_method("take_damage"):
			body.take_damage(DAMAGE, &"chemical", global_position)
		break


func _spawn_acid_puddle() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var puddle := ObjectPool.get_instance_by_id(ObjectPool.SCENE_ACID_PUDDLE)
	if puddle == null:
		return
	if puddle is Node2D:
		(puddle as Node2D).global_position = global_position
	parent.call_deferred("add_child", puddle)


func _build_visual() -> void:
	if sprite == null:
		return

	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var outer := Color(0.38, 0.52, 0.08, 1.0)
	var mid := Color(0.78, 0.96, 0.28, 1.0)
	var inner := Color(0.95, 1.0, 0.70, 1.0)
	for y in range(12):
		for x in range(12):
			var dist := Vector2(x - 5.5, y - 5.5).length()
			if dist <= 5.0:
				image.set_pixel(x, y, outer)
			if dist <= 3.6:
				image.set_pixel(x, y, mid)
			if dist <= 1.8:
				image.set_pixel(x, y, inner)
	sprite.texture = ImageTexture.create_from_image(image)
