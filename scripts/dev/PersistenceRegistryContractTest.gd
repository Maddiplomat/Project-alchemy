extends Node

class ValidProvider:
	extends RefCounted

	const PERSISTENCE_KEY := &"valid_provider"

	var state: Dictionary = {
		"value": 7,
		"flag": true,
	}
	var restored_state: Dictionary = {}

	func get_persistence_key() -> StringName:
		return PERSISTENCE_KEY

	func capture_persistent_state() -> Dictionary:
		return state.duplicate(true)

	func restore_persistent_state(data: Dictionary) -> void:
		restored_state = data.duplicate(true)


class InvalidShapeProvider:
	extends RefCounted

	const PERSISTENCE_KEY := &"invalid_shape"

	func get_persistence_key() -> StringName:
		return PERSISTENCE_KEY

	func capture_persistent_state() -> Array:
		return [1, 2, 3]

	func restore_persistent_state(_data: Dictionary) -> void:
		pass


var _failures := 0


func _ready() -> void:
	_run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var registered_entries: Array[Dictionary] = PersistenceRegistry.get_entries()
	var registered_keys := _sorted_entry_keys(registered_entries)
	_assert(
		registered_keys == [
			"cold_system",
			"discovery_log",
			"element_database",
			"game_manager",
			"power_switchboard",
			"research_objectives",
			"weather_system",
			"world_system",
		],
		"Expected PersistenceRegistry to expose the stable singleton persistence keys."
	)
	_assert(
		PersistenceRegistry.validate_entries(registered_entries, false).is_empty(),
		"Expected registered persistence entries to validate cleanly."
	)

	var duplicate_entries: Array = [
		{
			"key": &"duplicate_key",
			"section": PersistenceRegistry.SECTION_GLOBAL_SYSTEMS,
			"provider_type": PersistenceRegistry.PROVIDER_TYPE_DIRECT,
			"provider": ValidProvider.new(),
		},
		{
			"key": &"duplicate_key",
			"section": PersistenceRegistry.SECTION_GAME_MANAGER,
			"provider_type": PersistenceRegistry.PROVIDER_TYPE_DIRECT,
			"provider": ValidProvider.new(),
		},
	]
	var duplicate_errors := PersistenceRegistry.validate_entries(duplicate_entries, false)
	_assert(
		_has_error_containing(duplicate_errors, "Duplicate persistence key 'duplicate_key'"),
		"Expected duplicate persistence keys to fail validation loudly."
	)

	var invalid_shape_entries: Array = [
		{
			"key": &"invalid_shape",
			"section": PersistenceRegistry.SECTION_GLOBAL_SYSTEMS,
			"provider_type": PersistenceRegistry.PROVIDER_TYPE_DIRECT,
			"provider": InvalidShapeProvider.new(),
		},
	]
	var invalid_sections := PersistenceRegistry.capture_sections_from_entries(invalid_shape_entries, false)
	_assert(
		(invalid_sections.get("global_systems", {}) as Dictionary).get("invalid_shape", {}) == {},
		"Expected invalid capture shapes to be rejected by the persistence registry."
	)

	var restore_shape_errors := PersistenceRegistry.validate_restore_payload({
		"invalid_shape": ["not", "a", "dictionary"],
	}, invalid_shape_entries, false)
	_assert(
		_has_error_containing(restore_shape_errors, "Persistence state for key 'invalid_shape' must be a dictionary."),
		"Expected invalid restore shapes to fail validation loudly."
	)

	var source_provider := ValidProvider.new()
	source_provider.state = {
		"value": 42,
		"flag": false,
	}
	var target_provider := ValidProvider.new()
	target_provider.state = {}
	var capture_restore_entries: Array = [
		{
			"key": &"valid_provider",
			"section": PersistenceRegistry.SECTION_GLOBAL_SYSTEMS,
			"provider_type": PersistenceRegistry.PROVIDER_TYPE_DIRECT,
			"provider": source_provider,
		},
	]
	var captured_sections := PersistenceRegistry.capture_sections_from_entries(capture_restore_entries, false)
	var restore_payload := _flatten_sections(captured_sections)
	capture_restore_entries[0]["provider"] = target_provider
	var restored := PersistenceRegistry.restore_flattened_state_from_entries(restore_payload, capture_restore_entries, false)
	_assert(restored, "Expected persistence registry restore to succeed for valid providers.")
	_assert(
		target_provider.restored_state == source_provider.state,
		"Expected capture and restore to use the same registry contract."
	)

	if _failures == 0:
		print("PersistenceRegistryContractTest passed.")


func _flatten_sections(sections: Dictionary) -> Dictionary:
	var payload := {}
	payload["game_manager"] = (sections.get("game_manager", {}) as Dictionary).duplicate(true)
	payload["world_system"] = (sections.get("world_system", {}) as Dictionary).duplicate(true)
	var global_systems := sections.get("global_systems", {}) as Dictionary
	for key in global_systems.keys():
		if global_systems[key] is Dictionary:
			payload[str(key)] = (global_systems[key] as Dictionary).duplicate(true)
	return payload


func _sorted_entry_keys(entries: Array[Dictionary]) -> Array[String]:
	var keys: Array[String] = []
	for entry in entries:
		keys.append(str(entry.get("key", "")))
	keys.sort()
	return keys


func _has_error_containing(errors: Array[String], pattern: String) -> bool:
	for message in errors:
		if message.contains(pattern):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
