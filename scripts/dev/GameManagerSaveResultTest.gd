extends Node

var _failures := 0


func _ready() -> void:
	_run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var signal_results: Array[Dictionary] = []
	var callback := func(result: Dictionary) -> void:
		signal_results.append(result.duplicate(true))

	GameManager.save_completed.connect(callback)
	var result := GameManager.request_save(GameManager.SaveTrigger.MANUAL)
	GameManager.save_completed.disconnect(callback)

	_assert(not bool(result.get(&"success", true)), "Expected save to fail when no WorldSaveData service is registered.")
	_assert(str(result.get(&"error", "")).contains("WorldSaveData"), "Expected failure result to explain missing WorldSaveData.")
	_assert(str(result.get(&"absolute_path", "")).contains("slot_1.json"), "Expected save result to include absolute slot path.")
	_assert(signal_results.size() == 1, "Expected save_completed to emit exactly once.")
	if signal_results.size() == 1:
		_assert(signal_results[0] == result, "Expected save_completed payload to match request_save result.")

	if _failures == 0:
		print("GameManagerSaveResultTest passed.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
