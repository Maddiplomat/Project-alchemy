class_name SaveSystem
extends RefCounted

const WorldSaveDataScript = preload("res://scripts/WorldSaveData.gd")

const SAVE_DIRECTORY := "user://saves"
const SAVE_FILE_TEMPLATE := "user://saves/slot_%d.json"
const BACKUP_SAVE_FILE_TEMPLATE := "user://saves/slot_%d.bak.json"
const LEGACY_SAVE_FILE_TEMPLATE := "user://saves/slot_%d.save"

var game_manager: Node
var _is_saving := false
var _active_save_task_id := -1


func _init(owner: Node) -> void:
	game_manager = owner


func request_load_game(slot_id: int) -> void:
	game_manager.set_active_save_slot(slot_id)
	if not has_save_data(slot_id):
		return
	game_manager.set_game_state(game_manager.GameState.LOADING)
	_load_game_from_slot(slot_id)


func request_save(trigger: int) -> Dictionary:
	if _is_saving:
		return _queue_save_result({
			&"success": false,
			&"trigger": trigger,
			&"slot_id": game_manager.active_save_slot,
			&"path": get_save_file_path(game_manager.active_save_slot),
			&"absolute_path": ProjectSettings.globalize_path(get_save_file_path(game_manager.active_save_slot)),
			&"error": "A save is already in progress.",
			&"skipped": true,
		})
	if game_manager._is_automatic_save_trigger(trigger) and not game_manager._automatic_saves_enabled:
		return _queue_save_result({
			&"success": false,
			&"trigger": trigger,
			&"slot_id": game_manager.active_save_slot,
			&"path": get_save_file_path(game_manager.active_save_slot),
			&"absolute_path": ProjectSettings.globalize_path(get_save_file_path(game_manager.active_save_slot)),
			&"error": "Automatic saves are disabled until this session is manually saved or loaded.",
			&"skipped": true,
		})
	game_manager._seconds_since_autosave_request = 0
	var world_save_data := EventBus.get_world_save_data()
	if world_save_data != null and world_save_data.has_method("sync_runtime_state"):
		world_save_data.sync_runtime_state()
	game_manager.save_requested.emit(trigger)
	return game_manager.last_save_result.duplicate(true)


func is_saving() -> bool:
	return _is_saving


func has_save_data(slot_id: int) -> bool:
	return FileAccess.file_exists(get_save_file_path(slot_id)) \
		or FileAccess.file_exists(get_legacy_save_file_path(slot_id))


func get_save_metadata(slot_id: int) -> Dictionary:
	if not has_save_data(slot_id):
		return {}
	var save_data := read_normalized_save_envelope(slot_id, true)
	if save_data.is_empty():
		return {}
	return (save_data.get("metadata", {}) as Dictionary).duplicate(true)


func has_any_save_data() -> bool:
	for slot_id in range(1, game_manager.max_save_slots + 1):
		if has_save_data(slot_id):
			return true
	return false


func get_continue_slot() -> int:
	var best_slot := -1
	var best_saved_at := -1
	for slot_id in range(1, game_manager.max_save_slots + 1):
		var metadata := get_save_metadata(slot_id)
		if metadata.is_empty():
			continue
		var saved_at_unix := int(metadata.get("saved_at_unix", 0))
		if saved_at_unix > best_saved_at:
			best_saved_at = saved_at_unix
			best_slot = slot_id
	if best_slot != -1:
		return best_slot
	return game_manager.active_save_slot if has_save_data(game_manager.active_save_slot) else -1


func perform_save(trigger: int) -> void:
	if _is_saving:
		_queue_save_result({
			&"success": false,
			&"trigger": trigger,
			&"slot_id": game_manager.active_save_slot,
			&"path": get_save_file_path(game_manager.active_save_slot),
			&"absolute_path": ProjectSettings.globalize_path(get_save_file_path(game_manager.active_save_slot)),
			&"error": "A save is already in progress.",
			&"skipped": true,
		})
		return
	var world_save_data := EventBus.get_world_save_data()
	if world_save_data == null or not world_save_data.has_method("capture_runtime_state"):
		_queue_save_result(_failure_result(trigger, "WorldSaveData service is unavailable."))
		return
	var save_data: Dictionary = world_save_data.capture_runtime_state()
	if save_data.is_empty():
		_queue_save_result(_failure_result(trigger, "WorldSaveData produced an empty save payload."))
		return

	# JSON conversion stays on the main thread. Only filesystem work crosses to the worker.
	var serialized_save_data := stringify_save_data_for_storage(save_data, "\t")
	var save_path := get_save_file_path(game_manager.active_save_slot)
	var absolute_save_path := ProjectSettings.globalize_path(save_path)
	var context := {
		&"trigger": trigger,
		&"slot_id": game_manager.active_save_slot,
		&"path": save_path,
		&"absolute_path": absolute_save_path,
		&"backup_absolute_path": ProjectSettings.globalize_path(get_backup_save_file_path(game_manager.active_save_slot)),
		&"directory_absolute_path": ProjectSettings.globalize_path(SAVE_DIRECTORY),
	}
	_is_saving = true
	game_manager.last_save_result = {
		&"success": true,
		&"pending": true,
		&"trigger": trigger,
		&"slot_id": game_manager.active_save_slot,
		&"path": save_path,
		&"absolute_path": absolute_save_path,
		&"error": "",
	}
	_active_save_task_id = WorkerThreadPool.add_task(_write_save_payload.bind(serialized_save_data, context), false, "Save slot %d" % game_manager.active_save_slot)
	if _active_save_task_id >= 0:
		return
	_is_saving = false
	_queue_save_result(_failure_result(trigger, "Unable to queue the background save task."))


func _write_save_payload(serialized_save_data: String, context: Dictionary) -> void:
	var result: Dictionary = context.duplicate(true)
	var directory_path := str(context.get(&"directory_absolute_path", ""))
	if not DirAccess.dir_exists_absolute(directory_path):
		var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
		if directory_error != OK:
			result[&"success"] = false
			result[&"error"] = "Failed to create save directory: %s" % directory_path
			result[&"error_code"] = directory_error
			call_deferred("_finish_async_save", result)
			return

	_copy_existing_save_to_backup(str(context.get(&"absolute_path", "")), str(context.get(&"backup_absolute_path", "")))
	var file := FileAccess.open(str(context.get(&"absolute_path", "")), FileAccess.WRITE)
	if file == null:
		result[&"success"] = false
		result[&"error"] = "Failed to open save file for writing: %s" % str(context.get(&"absolute_path", ""))
		result[&"error_code"] = FileAccess.get_open_error()
		call_deferred("_finish_async_save", result)
		return
	file.store_string(serialized_save_data)
	file.close()
	result[&"success"] = true
	result[&"error"] = ""
	result[&"saved_at_unix"] = Time.get_unix_time_from_system()
	call_deferred("_finish_async_save", result)


func _copy_existing_save_to_backup(source_path: String, backup_path: String) -> void:
	if not FileAccess.file_exists(source_path):
		return
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return
	var source_text := source_file.get_as_text()
	source_file.close()
	var backup_file := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup_file == null:
		return
	backup_file.store_string(source_text)
	backup_file.close()


func _finish_async_save(result: Dictionary) -> void:
	_active_save_task_id = -1
	_is_saving = false
	if bool(result.get(&"success", false)):
		if int(result.get(&"trigger", -1)) == game_manager.SaveTrigger.MANUAL:
			game_manager._automatic_saves_enabled = true
		game_manager.clear_dirty()
	else:
		push_warning(str(result.get(&"error", "Save failed.")))
	_set_save_result(result)


func _failure_result(trigger: int, message: String) -> Dictionary:
	return {
		&"success": false,
		&"trigger": trigger,
		&"slot_id": game_manager.active_save_slot,
		&"path": get_save_file_path(game_manager.active_save_slot),
		&"absolute_path": ProjectSettings.globalize_path(get_save_file_path(game_manager.active_save_slot)),
		&"error": message,
	}


func _load_game_from_slot(slot_id: int) -> void:
	var normalized_save_data := read_normalized_save_envelope(slot_id, true)
	var save_data := extract_world_save_data(normalized_save_data)
	if save_data.is_empty():
		push_warning("Save payload is invalid for slot %d" % slot_id)
		game_manager.set_game_state(game_manager.GameState.MAIN_MENU)
		return
	var current_scene_path := str((normalized_save_data.get("metadata", {}) as Dictionary).get("current_scene_path", "res://scenes/World.tscn"))
	var world_data := save_data.get("world", {}) as Dictionary
	var world_system := EventBus.get_world_system()
	if world_system != null and world_system.has_method("set_seed_for_scene") and not world_data.is_empty():
		var saved_seed := str(world_data.get("seed", ""))
		if not saved_seed.is_empty():
			world_system.set_seed_for_scene(current_scene_path, int(saved_seed))
	var travel_context := {
		&"skip_post_restore_save": true,
		&"source": &"load_game",
	}
	if world_system != null and world_system.has_method("queue_pending_restore_state"):
		world_system.queue_pending_restore_state(save_data, travel_context)
	else:
		EventBus.set_gameplay_handoff({
			&"pending_restore_state": save_data.duplicate(true),
			&"pending_travel_context": travel_context,
		})
	var scene_error := game_manager.get_tree().change_scene_to_file(current_scene_path)
	if scene_error != OK:
		push_warning("Failed to change scene while loading save slot %d" % slot_id)
		game_manager.set_game_state(game_manager.GameState.MAIN_MENU)


func get_save_file_path(slot_id: int) -> String:
	return SAVE_FILE_TEMPLATE % clampi(slot_id, 1, game_manager.max_save_slots)


func get_backup_save_file_path(slot_id: int) -> String:
	return BACKUP_SAVE_FILE_TEMPLATE % clampi(slot_id, 1, game_manager.max_save_slots)


func get_legacy_save_file_path(slot_id: int) -> String:
	return LEGACY_SAVE_FILE_TEMPLATE % clampi(slot_id, 1, game_manager.max_save_slots)


func _set_save_result(result: Dictionary) -> Dictionary:
	game_manager.last_save_result = result.duplicate(true)
	game_manager.save_completed.emit(game_manager.last_save_result.duplicate(true))
	return game_manager.last_save_result.duplicate(true)


func _queue_save_result(result: Dictionary) -> Dictionary:
	game_manager.last_save_result = result.duplicate(true)
	call_deferred("_emit_queued_save_result", game_manager.last_save_result.duplicate(true))
	return game_manager.last_save_result.duplicate(true)


func _emit_queued_save_result(result: Dictionary) -> void:
	game_manager.save_completed.emit(result.duplicate(true))


func read_normalized_save_envelope(slot_id: int, rewrite_if_needed: bool = false) -> Dictionary:
	var raw_save_data := _read_save_file(slot_id)
	if raw_save_data.is_empty():
		return {}
	var normalized_save_data := normalize_save_envelope(raw_save_data)
	if rewrite_if_needed and _save_envelope_requires_rewrite(raw_save_data, normalized_save_data):
		_write_normalized_save_envelope(slot_id, normalized_save_data)
	return normalized_save_data


func _read_save_file(slot_id: int) -> Dictionary:
	var json_path := get_save_file_path(slot_id)
	if FileAccess.file_exists(json_path):
		return _read_json_save_file(json_path)
	var legacy_path := get_legacy_save_file_path(slot_id)
	if FileAccess.file_exists(legacy_path):
		return _read_legacy_save_file(legacy_path)
	return {}


func _read_json_save_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null:
		return {}
	var restored: Variant = decode_save_data_from_storage(parsed)
	if not (restored is Dictionary):
		return {}
	var restored_data := restored as Dictionary
	return restored_data if _validate_read_save_data(restored_data, path) else {}


func _read_legacy_save_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var payload: Variant = file.get_var()
	file.close()
	if not (payload is Dictionary):
		return {}
	var restored_data := payload as Dictionary
	return restored_data if _validate_read_save_data(restored_data, path) else {}


func _validate_read_save_data(save_data: Dictionary, path: String) -> bool:
	return bool(_with_world_save_data_codec(func(world_save_data: Node) -> bool:
		if world_save_data == null or not world_save_data.has_method("validate"):
			return false
		if bool(world_save_data.validate(save_data)):
			return true
		var errors: Array = world_save_data.get_validation_errors() if world_save_data.has_method("get_validation_errors") else []
		push_warning("Rejected invalid save '%s': %s" % [path, "; ".join(errors)])
		return false
	))


func extract_world_save_data(save_data: Dictionary) -> Dictionary:
	return _with_world_save_data_codec(func(world_save_data: Node) -> Dictionary:
		if world_save_data == null or not world_save_data.has_method("build_restore_payload"):
			return {}
		return world_save_data.build_restore_payload(save_data)
	)


func normalize_save_envelope(save_data: Dictionary) -> Dictionary:
	if save_data.is_empty():
		return {}
	return _with_world_save_data_codec(func(world_save_data: Node) -> Dictionary:
		if world_save_data == null or not world_save_data.has_method("normalize_save_envelope"):
			return {}
		return world_save_data.normalize_save_envelope(save_data)
	)


func _save_envelope_requires_rewrite(raw_save_data: Dictionary, normalized_save_data: Dictionary) -> bool:
	if raw_save_data.is_empty() or normalized_save_data.is_empty():
		return false
	return stringify_save_data_for_storage(raw_save_data) != stringify_save_data_for_storage(normalized_save_data)


func _write_normalized_save_envelope(slot_id: int, normalized_save_data: Dictionary) -> void:
	var file := FileAccess.open(get_save_file_path(slot_id), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(stringify_save_data_for_storage(normalized_save_data, "\t"))
	file.close()


func _with_world_save_data_codec(callback: Callable) -> Variant:
	var world_save_data: Node = EventBus.get_world_save_data()
	var owns_temporary := false
	if world_save_data == null:
		world_save_data = WorldSaveDataScript.new()
		owns_temporary = true
	var result: Variant = callback.call(world_save_data)
	if owns_temporary and is_instance_valid(world_save_data):
		world_save_data.free()
	return result


func stringify_save_data_for_storage(save_data: Dictionary, indent: String = "") -> String:
	return str(_with_world_save_data_codec(func(world_save_data: Node) -> String:
		if world_save_data != null and world_save_data.has_method("stringify_save_data"):
			return String(world_save_data.stringify_save_data(save_data, indent))
		return JSON.stringify(_variant_to_json_value(save_data), indent)
	))


func decode_save_data_from_storage(value: Variant) -> Variant:
	return _with_world_save_data_codec(func(world_save_data: Node) -> Variant:
		if world_save_data != null and world_save_data.has_method("decode_storage_value"):
			return world_save_data.decode_storage_value(value)
		return _json_value_to_variant(value)
	)


func _variant_to_json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return {"__type": "StringName", "value": str(value)}
		TYPE_DICTIONARY:
			var json_dict := {}
			for raw_key in (value as Dictionary).keys():
				json_dict[str(raw_key)] = _variant_to_json_value((value as Dictionary)[raw_key])
			return json_dict
		TYPE_ARRAY:
			var json_array: Array = []
			for item in (value as Array):
				json_array.append(_variant_to_json_value(item))
			return json_array
		TYPE_VECTOR2:
			var vector2 := value as Vector2
			return {"__type": "Vector2", "x": vector2.x, "y": vector2.y}
		TYPE_VECTOR2I:
			var vector2i := value as Vector2i
			return {"__type": "Vector2i", "x": vector2i.x, "y": vector2i.y}
		_:
			return {"__type": "VariantString", "value": var_to_str(value)}


func _json_value_to_variant(value: Variant) -> Variant:
	if value is Array:
		var restored_array: Array = []
		for item in value:
			restored_array.append(_json_value_to_variant(item))
		return restored_array
	if not value is Dictionary:
		return value
	var value_dict := value as Dictionary
	match str(value_dict.get("__type", "")):
		"StringName":
			return StringName(str(value_dict.get("value", "")))
		"Vector2":
			return Vector2(float(value_dict.get("x", 0.0)), float(value_dict.get("y", 0.0)))
		"Vector2i":
			return Vector2i(int(value_dict.get("x", 0)), int(value_dict.get("y", 0)))
		"VariantString":
			return str_to_var(str(value_dict.get("value", "")))
		_:
			var restored_dict := {}
			for raw_key in value_dict.keys():
				restored_dict[raw_key] = _json_value_to_variant(value_dict[raw_key])
			return restored_dict
