extends Node2D

const PlayerScene = preload("res://scenes/Player.tscn")
const EnemyScanTestEnemyScript = preload("res://scripts/dev/EnemyScanTestEnemy.gd")

var _failures := 0


func _ready() -> void:
	await _run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var player = PlayerScene.instantiate() as CharacterBody2D
	player.global_position = Vector2.ZERO
	add_child(player)

	var enemy_119 := _spawn_enemy("Enemy119", Vector2(119.0, 0.0))
	var enemy_121 := _spawn_enemy("Enemy121", Vector2(121.0, 0.0))

	await get_tree().process_frame
	await get_tree().process_frame

	if GameManager != null and GameManager.has_method("unlock_advanced_scanner"):
		GameManager.unlock_advanced_scanner()

	var scanner := player.get_node("ScannerTool")
	scanner.call("_begin_scan")
	await get_tree().process_frame

	var active_targets: Array = scanner.call("get_active_scan_targets")
	print("EnemyScanRangeTest targets=%s" % _target_names(active_targets))

	_assert(active_targets.has(enemy_119), "Expected enemy at 119px to be detected.")
	_assert(not active_targets.has(enemy_121), "Expected enemy at 121px to remain undetected.")

	var canvas := get_node_or_null("ScannerCanvas") as CanvasLayer
	_assert(canvas != null, "Expected ScannerCanvas to be created for scan overlay.")
	if canvas != null:
		var overlay := canvas.get_node_or_null("ScanOverlay_Enemy119") as PanelContainer
		_assert(overlay != null, "Expected composition overlay for 119px enemy.")
		_assert(canvas.get_node_or_null("ScanOverlay_Enemy121") == null, "Expected no overlay for 121px enemy.")
		if overlay != null:
			_assert(overlay.get_node_or_null("MarginContainer/VBoxContainer/CompositionBar") != null, "Expected composition bar in enemy scan overlay.")
			_assert(overlay.get_node_or_null("MarginContainer/VBoxContainer/WeaknessesRow/Badges") != null, "Expected weakness badges row in enemy scan overlay.")
			_assert(overlay.get_node_or_null("MarginContainer/VBoxContainer/ImmunitiesRow/Badges") != null, "Expected immunity badges row in enemy scan overlay.")

	if _failures == 0:
		print("EnemyScanRangeTest passed.")


func _spawn_enemy(node_name: String, world_pos: Vector2) -> Area2D:
	var enemy := Area2D.new()
	enemy.name = node_name
	enemy.collision_layer = 4
	enemy.position = world_pos
	enemy.set_script(EnemyScanTestEnemyScript)

	var collision_shape := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 0.1
	collision_shape.shape = shape
	enemy.add_child(collision_shape)

	add_child(enemy)
	return enemy


func _target_names(targets: Array) -> PackedStringArray:
	var names: PackedStringArray = []
	for target in targets:
		if target is Node:
			names.append((target as Node).name)
	return names


func _assert(condition: bool, message: String) -> void:
	if condition:
		return

	_failures += 1
	push_error(message)
