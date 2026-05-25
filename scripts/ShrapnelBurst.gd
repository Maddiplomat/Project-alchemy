extends Node2D

const SHARD_COUNT := 8
const SPAWN_OFFSET := 12.0
const SHRAPNEL_PROJECTILE_SCRIPT := preload("res://scripts/ShrapnelProjectile.gd")


func _ready() -> void:
	_spawn_shards()
	queue_free()


func _spawn_shards() -> void:
	var parent := get_parent()
	if parent == null:
		return

	for index in range(SHARD_COUNT):
		var angle := (TAU / float(SHARD_COUNT)) * float(index)
		var direction := Vector2.RIGHT.rotated(angle)
		SHRAPNEL_PROJECTILE_SCRIPT.spawn(parent, global_position + direction * SPAWN_OFFSET, direction)
