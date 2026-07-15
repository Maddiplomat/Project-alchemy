extends Node

var _failures := 0


func _ready() -> void:
	await _run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var game_manager: Node = get_tree().root.get_node_or_null("GameManager")
	_assert(game_manager != null, "Expected GameManager autoload to be available during the test run.")
	if game_manager == null:
		return

	var signal_results: Array[Dictionary] = []
	var callback := func(result: Dictionary) -> void:
		signal_results.append(result.duplicate(true))

	var result: Dictionary = game_manager.request_save(game_manager.SaveTrigger.MANUAL)
	game_manager.save_completed.connect(callback)
	await get_tree().process_frame
	if game_manager.save_completed.is_connected(callback):
		game_manager.save_completed.disconnect(callback)

	_assert(not bool(result.get(&"success", true)), "Expected save to fail when no WorldSaveData service is registered.")
	_assert(str(result.get(&"error", "")).contains("WorldSaveData"), "Expected failure result to explain missing WorldSaveData.")
	_assert(str(result.get(&"absolute_path", "")).contains("slot_1.json"), "Expected save result to include absolute slot path.")
	_assert(signal_results.size() == 1, "Expected save_completed to emit exactly once.")
	if signal_results.size() == 1:
		_assert(signal_results[0] == result, "Expected save_completed payload to match request_save result.")

	signal_results.clear()
	game_manager.save_completed.connect(callback)
	game_manager.game_state = game_manager.GameState.PLAYING
	var save_event := InputEventAction.new()
	save_event.action = &"manual_save"
	save_event.pressed = true
	game_manager._input(save_event)
	await get_tree().process_frame
	if game_manager.save_completed.is_connected(callback):
		game_manager.save_completed.disconnect(callback)

	_assert(signal_results.size() == 1, "Expected manual_save input to route through GameManager and emit save_completed once.")
	if signal_results.size() == 1:
		_assert(int(signal_results[0].get(&"trigger", -1)) == game_manager.SaveTrigger.MANUAL, "Expected manual_save input to use SaveTrigger.MANUAL.")
		_assert(not bool(signal_results[0].get(&"success", true)), "Expected manual_save input path to surface the same save failure when no WorldSaveData service is registered.")

	if _failures == 0:
		print("GameManagerSaveResultTest passed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
