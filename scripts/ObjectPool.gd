extends Node

## Reuses short-lived combat nodes to avoid allocation and GC spikes during combat.

const DEFAULT_MAX_PER_SCENE := 32
const SCENE_PROJECTILE := &"projectile"
const SCENE_RUST_BOLT := &"rust_bolt"
const SCENE_SULFURIC_BOLT := &"sulfuric_bolt"
const SCENE_SHRAPNEL_PROJECTILE := &"shrapnel_projectile"
const SCENE_SHRAPNEL_BURST := &"shrapnel_burst"
const SCENE_ACID_SPIT := &"acid_spit"
const SCENE_ACID_PUDDLE := &"acid_puddle"
const SCENE_DAMAGE_NUMBER := &"damage_number"
const SCENE_CHEMICAL_EXPLOSION := &"chemical_explosion"
const SCENE_TOXIC_CLOUD := &"toxic_cloud"
const SCENE_FIRE_PATCH := &"fire_patch"

## The only place pooled scenes are preloaded. Consumers request them by ID.
const SCENE_REGISTRY := {
	SCENE_PROJECTILE: preload("res://scenes/Projectile.tscn"),
	SCENE_RUST_BOLT: preload("res://scenes/RustBolt.tscn"),
	SCENE_SULFURIC_BOLT: preload("res://scenes/SulfuricBolt.tscn"),
	SCENE_SHRAPNEL_PROJECTILE: preload("res://scenes/ShrapnelProjectile.tscn"),
	SCENE_SHRAPNEL_BURST: preload("res://scenes/ShrapnelBurst.tscn"),
	SCENE_ACID_SPIT: preload("res://scenes/AcidSpit.tscn"),
	SCENE_ACID_PUDDLE: preload("res://scenes/AcidPuddle.tscn"),
	SCENE_DAMAGE_NUMBER: preload("res://scenes/DamageNumber.tscn"),
	SCENE_CHEMICAL_EXPLOSION: preload("res://scenes/ChemicalExplosion.tscn"),
	SCENE_TOXIC_CLOUD: preload("res://scenes/ToxicCloud.tscn"),
	SCENE_FIRE_PATCH: preload("res://scenes/FirePatch.tscn"),
}

const POOL_CAPS := {
	"res://scenes/Projectile.tscn": 48,
	"res://scenes/RustBolt.tscn": 48,
	"res://scenes/SulfuricBolt.tscn": 48,
	"res://scenes/ShrapnelProjectile.tscn": 96,
	"res://scenes/ShrapnelBurst.tscn": 16,
	"res://scenes/AcidSpit.tscn": 24,
	"res://scenes/AcidPuddle.tscn": 24,
	"res://scenes/DamageNumber.tscn": 48,
	"res://scenes/ChemicalExplosion.tscn": 16,
	"res://scenes/ToxicCloud.tscn": 12,
	"res://scenes/FirePatch.tscn": 24,
}

var _available: Dictionary = {}
var _scene_key_by_instance_id: Dictionary = {}
var _pooled_instance_ids: Dictionary = {}


func get_instance_by_id(scene_id: StringName) -> Node:
	var scene := SCENE_REGISTRY.get(scene_id) as PackedScene
	if scene == null:
		push_error("ObjectPool has no scene registered for '%s'." % scene_id)
		return null
	return get_instance(scene)


func get_instance(scene: PackedScene) -> Node:
	if scene == null:
		return null

	var scene_key := _scene_key(scene)
	var available: Array = _available.get(scene_key, [])
	while not available.is_empty():
		var instance := available.pop_back() as Node
		if instance == null or not is_instance_valid(instance):
			continue
		_available[scene_key] = available
		_pooled_instance_ids.erase(instance.get_instance_id())
		_prepare_for_use(instance)
		return instance

	_available[scene_key] = available
	var instance := scene.instantiate() as Node
	if instance == null:
		return null
	_scene_key_by_instance_id[instance.get_instance_id()] = scene_key
	instance.tree_entered.connect(_on_pooled_instance_entered_tree.bind(instance))
	_prepare_for_use(instance)
	return instance


func release(instance: Node) -> void:
	if instance == null or not is_instance_valid(instance) or instance.is_queued_for_deletion():
		return

	var instance_id := instance.get_instance_id()
	if not _scene_key_by_instance_id.has(instance_id):
		instance.queue_free()
		return
	if _pooled_instance_ids.has(instance_id):
		return

	var scene_key: String = _scene_key_by_instance_id[instance_id]
	_reset_instance(instance)
	if instance.get_parent() != null:
		instance.get_parent().remove_child(instance)

	var available: Array = _available.get(scene_key, [])
	if available.size() >= int(POOL_CAPS.get(scene_key, DEFAULT_MAX_PER_SCENE)):
		_scene_key_by_instance_id.erase(instance_id)
		_pooled_instance_ids.erase(instance_id)
		instance.queue_free()
		return

	available.append(instance)
	_available[scene_key] = available
	_pooled_instance_ids[instance_id] = true


func _prepare_for_use(instance: Node) -> void:
	_reset_instance(instance)
	instance.process_mode = Node.PROCESS_MODE_INHERIT
	instance.set_process(true)
	instance.set_physics_process(true)
	# _ready normally runs once. Request it again so pooled effects restart timers and particles.
	instance.request_ready()


func _reset_instance(instance: Node) -> void:
	if instance.has_method("_pool_reset"):
		instance.call("_pool_reset")
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance is CanvasItem:
		(instance as CanvasItem).visible = false


func _scene_key(scene: PackedScene) -> String:
	return scene.resource_path if not scene.resource_path.is_empty() else str(scene.get_instance_id())


func _on_pooled_instance_entered_tree(instance: Node) -> void:
	if instance is CanvasItem:
		(instance as CanvasItem).visible = true
