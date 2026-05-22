extends Node2D

const FurnaceScene = preload("res://scenes/Furnace.tscn")
const ChemBenchScene = preload("res://scenes/ChemBench.tscn")
const PlayerScene = preload("res://scenes/Player.tscn")

var _failures := 0


func _ready() -> void:
	await _run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var player = PlayerScene.instantiate() as CharacterBody2D
	add_child(player)

	var furnace = FurnaceScene.instantiate()
	add_child(furnace)

	var chem_bench = ChemBenchScene.instantiate()
	add_child(chem_bench)

	await get_tree().process_frame
	await get_tree().process_frame

	var furnace_shape := furnace.get_node("InteractionArea/CollisionShape2D").shape as RectangleShape2D
	var chem_bench_shape := chem_bench.get_node("InteractionArea/CollisionShape2D").shape as RectangleShape2D
	var player_shape := player.get_node("CollisionShape2D").shape as RectangleShape2D

	_assert(furnace_shape != null, "Expected Furnace interaction rectangle.")
	_assert(chem_bench_shape != null, "Expected ChemBench interaction rectangle.")
	_assert(player_shape != null, "Expected Player collision rectangle.")
	if furnace_shape == null or chem_bench_shape == null or player_shape == null:
		return

	print(
		"ChemBenchInteractionRangeTest sizes: furnace=%s chem_bench=%s player=%s"
		% [furnace_shape.size, chem_bench_shape.size, player_shape.size]
	)

	_assert(furnace_shape.size == Vector2(48.0, 48.0), "Expected Furnace interaction size 48x48.")
	_assert(chem_bench_shape.size == Vector2(56.0, 56.0), "Expected ChemBench interaction size 56x56.")

	var furnace_trigger_x := furnace_shape.size.x * 0.5 + player_shape.size.x * 0.5
	var chem_bench_trigger_x := chem_bench_shape.size.x * 0.5 + player_shape.size.x * 0.5
	print(
		"ChemBenchInteractionRangeTest trigger thresholds: furnace=%.1f chem_bench=%.1f"
		% [furnace_trigger_x, chem_bench_trigger_x]
	)

	_assert(is_equal_approx(furnace_trigger_x, 28.0), "Expected Furnace center threshold of 28px with player collider.")
	_assert(is_equal_approx(chem_bench_trigger_x, 32.0), "Expected ChemBench center threshold of 32px with player collider.")

	if _failures == 0:
		print("ChemBenchInteractionRangeTest passed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return

	_failures += 1
	push_error(message)
