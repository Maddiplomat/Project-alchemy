extends CharacterBody2D

const RUST_BOLT_SCRIPT := preload("res://scripts/RustBolt.gd")
const SULFURIC_BOLT_SCRIPT := preload("res://scripts/SulfuricBolt.gd")
const STEEL_SWORD_DAMAGE := 10.0
const STEEL_SWORD_DAMAGE_TYPE := &"physical_sharp"
const STEEL_SWORD_COOLDOWN := 0.3
const STEEL_SWORD_SWING_DURATION := 0.2
const WORLD_DROP_DISTANCE := 18.0

@export var max_speed: float = 200.0
@export var acceleration: float = 600.0
@export var friction: float = 1200.0

const OVER_CAPACITY_SPEED_MULTIPLIER := 0.5
const SPRINT_SPEED_MULTIPLIER := 1.5
@export var sprint_drop_chance: float = 0.002

signal drop_item(slot_index: int)
signal input_paused_changed(is_paused: bool)

@onready var melee_pivot: Node2D = $MeleePivot
@onready var sword_arc_visual: Line2D = $MeleePivot/SwordArcVisual
@onready var melee_hitbox: Area2D = $MeleePivot/MeleeHitbox
@onready var melee_hitbox_shape: CollisionShape2D = $MeleePivot/MeleeHitbox/CollisionShape2D
@onready var melee_animation_player: AnimationPlayer = $MeleePivot/MeleeAnimationPlayer

var _speed_multiplier := 1.0
var _sprint_multiplier := 1.0
var _terrain_speed_multiplier := 1.0
var _step_timer := 0.0
var _base_max_speed := 0.0
var _input_paused := false
var _attack_cooldown_remaining := 0.0
var _melee_swing_active := false
var _melee_hit_targets: Dictionary[int, bool] = {}


func _ready() -> void:
	add_to_group("player")
	_base_max_speed = max_speed
	drop_item.connect(_on_drop_item)
	InventoryManager.weight_changed.connect(_on_weight_changed)
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)
	melee_hitbox.body_entered.connect(_on_melee_hitbox_body_entered)
	_setup_melee_animation()


func _unhandled_input(event: InputEvent) -> void:
	if _input_paused:
		return
	if event.is_action_pressed("fire_projectile"):
		_use_held_weapon()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	if _input_paused:
		velocity = Vector2.ZERO
		_step_timer = 0.0
		move_and_slide()
		return

	_sprint_multiplier = SPRINT_SPEED_MULTIPLIER if Input.is_action_pressed(&'sprint') else 1.0
	_handle_sprint_risk()
	_update_terrain_speed_multiplier()
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	var current_max_speed := _base_max_speed * _speed_multiplier * _sprint_multiplier * _terrain_speed_multiplier

	if input_direction != Vector2.ZERO and not _input_paused:
		velocity = velocity.move_toward(input_direction * current_max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_step_timer = 0.0

	move_and_slide()


func _handle_sprint_risk() -> void:
	if _sprint_multiplier <= 1.0:
		return
	if not InventoryManager.is_over_capacity():
		return
	if randf() >= sprint_drop_chance:
		return

	var random_slot := randi() % InventoryManager.DEFAULT_SLOT_COUNT
	drop_item.emit(random_slot)


func _on_drop_item(slot_index: int) -> void:
	var slot_item := InventoryManager.get_slot_item(slot_index)
	if slot_item.is_empty():
		return

	if not _spawn_inventory_pickup(slot_item, _get_drop_spawn_position(), 1):
		return

	InventoryManager.remove_item(StringName(str(slot_item.get("id", ""))), 1)


func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	_speed_multiplier = OVER_CAPACITY_SPEED_MULTIPLIER if total_weight > carry_capacity else 1.0


func _spawn_inventory_pickup(item_data: Dictionary, world_position: Vector2, quantity: int) -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	var spawn_system := current_scene.get_node_or_null("ElementSpawnSystem")
	if spawn_system == null or not spawn_system.has_method("spawn_inventory_pickup"):
		return false

	return (spawn_system.call("spawn_inventory_pickup", item_data, world_position, quantity) as Node2D) != null


func _get_drop_spawn_position() -> Vector2:
	var direction := global_position.direction_to(get_global_mouse_position())
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	return global_position + direction * WORLD_DROP_DISTANCE


func _update_terrain_speed_multiplier() -> void:
	_terrain_speed_multiplier = 1.0
	var current_scene := get_tree().current_scene
	if current_scene == null or not current_scene.has_method("get_movement_speed_multiplier_at_world_position"):
		return
	_terrain_speed_multiplier = float(current_scene.get_movement_speed_multiplier_at_world_position(global_position))


func pause_input() -> void:
	_input_paused = true
	_sprint_multiplier = 1.0
	velocity = Vector2.ZERO
	input_paused_changed.emit(true)


func resume_input() -> void:
	_input_paused = false
	input_paused_changed.emit(false)


func is_input_paused() -> bool:
	return _input_paused


func _use_held_weapon() -> void:
	if _attack_cooldown_remaining > 0.0:
		return

	var held_item := InventoryManager.get_held_item()
	if held_item.is_empty():
		return
	var weapon_profile := _get_held_weapon_profile(held_item)
	var weapon_type := String(weapon_profile.get("weapon_type", ""))
	match weapon_type:
		"melee":
			_swing_melee_weapon(weapon_profile)
		"ranged":
			_fire_ranged_weapon(weapon_profile)


func _fire_ranged_weapon(weapon_profile: Dictionary) -> void:
	var held_item_id := StringName(str(InventoryManager.get_held_item_id()))
	if held_item_id.is_empty():
		return
	if not InventoryManager.remove_item(held_item_id, 1):
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		InventoryManager.add_item({
			&"id": held_item_id,
			&"display_name": str(weapon_profile.get("display_name", "Ranged Weapon")),
			&"category": int(weapon_profile.get("category", InventoryManager.InventoryItemCategory.CONSUMABLE)),
		}, 1)
		return

	var aim_target := get_global_mouse_position()
	var direction := global_position.direction_to(aim_target)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var spawn_origin := global_position + direction * 10.0
	var projectile_id := String(weapon_profile.get("projectile_id", ""))
	match projectile_id:
		"rust_bolt":
			RUST_BOLT_SCRIPT.spawn(current_scene, spawn_origin, aim_target)
		"sulfuric_bolt":
			SULFURIC_BOLT_SCRIPT.spawn(current_scene, spawn_origin, aim_target)
		_:
			InventoryManager.add_item(weapon_profile, 1)
			return

	_attack_cooldown_remaining = maxf(0.0, float(weapon_profile.get("attack_cooldown", 0.0)))


func _swing_melee_weapon(weapon_profile: Dictionary) -> void:
	_attack_cooldown_remaining = maxf(STEEL_SWORD_COOLDOWN, float(weapon_profile.get("attack_cooldown", STEEL_SWORD_COOLDOWN)))
	var aim_direction := global_position.direction_to(get_global_mouse_position())
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT
	melee_pivot.rotation = aim_direction.angle()
	sword_arc_visual.visible = true
	melee_hitbox.monitoring = true
	melee_hitbox_shape.disabled = false
	_melee_swing_active = true
	_melee_hit_targets.clear()
	melee_animation_player.play("steel_sword_swing")
	_apply_melee_hits(weapon_profile)

	var swing_timer := get_tree().create_timer(STEEL_SWORD_SWING_DURATION)
	swing_timer.timeout.connect(_finish_melee_swing)


func _finish_melee_swing() -> void:
	_melee_swing_active = false
	melee_hitbox.monitoring = false
	melee_hitbox_shape.disabled = true
	melee_hitbox.rotation_degrees = 0.0
	sword_arc_visual.rotation_degrees = 0.0
	sword_arc_visual.visible = false
	_melee_hit_targets.clear()


func _apply_melee_hits(weapon_profile: Dictionary) -> void:
	for body in _get_immediate_melee_targets():
		_apply_melee_hit_to_body(body, weapon_profile)


func _on_melee_hitbox_body_entered(body: Node) -> void:
	if not _melee_swing_active:
		return
	_apply_melee_hit_to_body(body, _get_held_weapon_profile(InventoryManager.get_held_item()))


func _apply_melee_hit_to_body(body: Node, weapon_profile: Dictionary) -> void:
	if body == null or not body.is_in_group(&"enemy"):
		return

	var instance_id := body.get_instance_id()
	if _melee_hit_targets.has(instance_id):
		return
	_melee_hit_targets[instance_id] = true

	var damage_type := StringName(str(weapon_profile.get("damage_type", STEEL_SWORD_DAMAGE_TYPE)))
	var base_damage := float(weapon_profile.get("base_damage", STEEL_SWORD_DAMAGE))
	var final_damage := DamageCalculator.calculate(base_damage, damage_type, body, body.global_position)
	var resolved_damage := int(final_damage)
	if resolved_damage <= 0:
		return

	var health_system := body.get_node_or_null("HealthSystem")
	if health_system == null:
		health_system = body.find_child("HealthSystem", true, false)
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(resolved_damage, damage_type)
	elif body.has_method("take_resolved_damage"):
		body.take_resolved_damage(resolved_damage, damage_type, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(resolved_damage, damage_type, global_position)
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(resolved_damage, damage_type)


func _get_held_weapon_profile(held_item: Dictionary) -> Dictionary:
	if held_item.is_empty():
		return {}

	var item_id := StringName(str(held_item.get("id", "")))
	if held_item.has("weapon_type"):
		return held_item

	match item_id:
		&"steel_sword":
			return {
				&"id": item_id,
				&"display_name": "Steel Sword",
				&"weapon_type": "melee",
				&"damage_type": String(STEEL_SWORD_DAMAGE_TYPE),
				&"base_damage": STEEL_SWORD_DAMAGE,
				&"attack_cooldown": STEEL_SWORD_COOLDOWN,
			}
		&"rust_bolt":
			return {
				&"id": item_id,
				&"display_name": "Rust Bolt",
				&"weapon_type": "ranged",
				&"projectile_id": "rust_bolt",
				&"damage_type": "oxidation",
				&"base_damage": 15.0,
			}
		&"sulfuric_bolt":
			return {
				&"id": item_id,
				&"display_name": "Sulfuric Bolt",
				&"weapon_type": "ranged",
				&"projectile_id": "sulfuric_bolt",
				&"damage_type": "chemical",
				&"base_damage": 22.0,
				&"attack_cooldown": 0.24,
			}
		_:
			return {}


func _setup_melee_animation() -> void:
	melee_animation_player.set_root_node(NodePath(".."))
	if melee_animation_player.has_animation("steel_sword_swing"):
		return

	var animation := Animation.new()
	animation.length = STEEL_SWORD_SWING_DURATION
	animation.loop_mode = Animation.LOOP_NONE
	var rotation_track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(rotation_track, NodePath("MeleeHitbox:rotation_degrees"))
	animation.track_insert_key(rotation_track, 0.0, -25.0)
	animation.track_insert_key(rotation_track, STEEL_SWORD_SWING_DURATION * 0.5, 0.0)
	animation.track_insert_key(rotation_track, STEEL_SWORD_SWING_DURATION, 25.0)
	var visual_track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(visual_track, NodePath("SwordArcVisual:rotation_degrees"))
	animation.track_insert_key(visual_track, 0.0, -25.0)
	animation.track_insert_key(visual_track, STEEL_SWORD_SWING_DURATION * 0.5, 0.0)
	animation.track_insert_key(visual_track, STEEL_SWORD_SWING_DURATION, 25.0)

	var animation_library := AnimationLibrary.new()
	animation_library.add_animation("steel_sword_swing", animation)
	melee_animation_player.add_animation_library("", animation_library)


func _get_immediate_melee_targets() -> Array:
	var results: Array = []
	if melee_hitbox_shape == null or melee_hitbox_shape.shape == null:
		return results

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = melee_hitbox_shape.shape
	query.transform = melee_hitbox_shape.global_transform
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = melee_hitbox.collision_mask

	var space_state := get_world_2d().direct_space_state
	for hit in space_state.intersect_shape(query):
		var collider = hit.get("collider")
		if collider != null:
			results.append(collider)
	return results
