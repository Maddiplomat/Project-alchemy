extends Node

const MCPRuntimeScript = preload("res://scripts/MCPRuntime.gd")
const ElementSpawnScript = preload("res://scripts/ElementSpawn.gd")
const ElementPickupScene = preload("res://scenes/ElementPickup.tscn")

var _failures := 0


func _ready() -> void:
	await _run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var runtime := MCPRuntimeScript.new()
	add_child(runtime)
	await get_tree().process_frame

	_assert(not runtime.has_node("EditorMCPRuntime"), "Expected MCP runtime bridge to avoid starting editor runtime during headless test execution.")
	_assert(runtime.has_method("push_runtime_log"), "Expected MCP runtime bridge to expose push_runtime_log().")
	runtime.push_runtime_log("info", "bridge smoke test")

	var element_spawn := ElementSpawnScript.new()
	add_child(element_spawn)
	await get_tree().process_frame
	var objects_layer := TileMapLayer.new()
	element_spawn._log_spawn_report({}, 0, objects_layer)
	objects_layer.free()
	element_spawn.queue_free()

	var pickup := ElementPickupScene.instantiate()
	add_child(pickup)
	await get_tree().process_frame
	pickup._log_shape_size_once()
	pickup.queue_free()

	runtime.queue_free()
	await get_tree().process_frame

	if _failures == 0:
		print("MCPRuntimeGuardTest passed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
