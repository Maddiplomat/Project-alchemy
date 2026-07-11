extends Node

const PersistenceContractScript = preload("res://scripts/PersistenceContract.gd")

const SECTION_GAME_MANAGER := &"game_manager"
const SECTION_WORLD_SYSTEM := &"world_system"
const SECTION_GLOBAL_SYSTEMS := &"global_systems"

const PROVIDER_TYPE_AUTOLOAD := &"autoload"
const PROVIDER_TYPE_SERVICE := &"service"
const PROVIDER_TYPE_DIRECT := &"direct"

var _entries: Array[Dictionary] = []


func _ready() -> void:
	_entries = _build_default_entries()
	var errors := validate_entries(_entries, false)
	_report_errors(errors)


func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _entries:
		result.append((entry as Dictionary).duplicate(true))
	return result


func validate_entries(entries: Array, fail_loudly: bool = true) -> Array[String]:
	var errors: Array[String] = []
	var seen_keys := {}
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			errors.append("Persistence registry entry must be a dictionary.")
			continue
		var entry := raw_entry as Dictionary
		var key := StringName(str(entry.get("key", "")))
		if key.is_empty():
			errors.append("Persistence registry entry is missing a stable persistence key.")
			continue
		if seen_keys.has(key):
			errors.append("Duplicate persistence key '%s' is registered." % String(key))
		else:
			seen_keys[key] = true
		var section := StringName(str(entry.get("section", "")))
		if not _is_valid_section(section):
			errors.append("Persistence key '%s' is registered to invalid section '%s'." % [String(key), String(section)])
		var provider_type := StringName(str(entry.get("provider_type", "")))
		if provider_type != PROVIDER_TYPE_AUTOLOAD and provider_type != PROVIDER_TYPE_SERVICE and provider_type != PROVIDER_TYPE_DIRECT:
			errors.append("Persistence key '%s' is registered with invalid provider type '%s'." % [String(key), String(provider_type)])
	if fail_loudly:
		_report_errors(errors)
	return errors


func build_empty_sections() -> Dictionary:
	return _build_empty_sections_from_entries(_entries)


func build_sections_from_flat_save(flat_save: Dictionary) -> Dictionary:
	var sections := build_empty_sections()
	for raw_entry in _entries:
		var entry := raw_entry as Dictionary
		var key := String(entry.get("key", ""))
		var section := StringName(str(entry.get("section", "")))
		var raw_value: Variant = flat_save.get(key, {})
		if not (raw_value is Dictionary):
			continue
		var state := (raw_value as Dictionary).duplicate(true)
		match section:
			SECTION_GAME_MANAGER:
				sections[String(SECTION_GAME_MANAGER)] = state
			SECTION_WORLD_SYSTEM:
				sections[String(SECTION_WORLD_SYSTEM)] = state
			SECTION_GLOBAL_SYSTEMS:
				var global_systems := sections.get(String(SECTION_GLOBAL_SYSTEMS), {}) as Dictionary
				global_systems[key] = state
				sections[String(SECTION_GLOBAL_SYSTEMS)] = global_systems
	return sections


func capture_persistent_sections() -> Dictionary:
	return capture_sections_from_entries(_entries)


func capture_sections_from_entries(entries: Array, fail_loudly: bool = true) -> Dictionary:
	var sections := _build_empty_sections_from_entries(entries)
	var errors: Array[String] = validate_entries(entries, false)
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var provider := _resolve_provider(entry)
		if provider == null:
			continue
		var key := StringName(str(entry.get("key", "")))
		var previous_error_count := errors.size()
		var captured_state := PersistenceContractScript.capture_provider_state(provider, key, errors)
		if errors.size() > previous_error_count:
			continue
		_assign_section_state(sections, entry, captured_state)
	if fail_loudly:
		_report_errors(errors)
	return sections


func validate_restore_payload(flat_state: Dictionary, entries: Array, fail_loudly: bool = true) -> Array[String]:
	var errors: Array[String] = validate_entries(entries, false)
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var key := String(entry.get("key", ""))
		if not flat_state.has(key):
			continue
		var state: Variant = flat_state.get(key, {})
		if not PersistenceContractScript.validate_restore_state_shape(state, StringName(key), errors):
			continue
		var provider := _resolve_provider(entry)
		if provider == null:
			continue
		PersistenceContractScript.validate_provider(provider, StringName(key), errors)
	if fail_loudly:
		_report_errors(errors)
	return errors


func restore_flattened_state(flat_state: Dictionary) -> bool:
	return restore_flattened_state_from_entries(flat_state, _entries)


func restore_flattened_state_from_entries(flat_state: Dictionary, entries: Array, fail_loudly: bool = true) -> bool:
	var errors: Array[String] = validate_restore_payload(flat_state, entries, false)
	if fail_loudly:
		_report_errors(errors)
	if not errors.is_empty():
		return false
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var key := String(entry.get("key", ""))
		if not flat_state.has(key):
			continue
		var provider := _resolve_provider(entry)
		if provider == null:
			continue
		PersistenceContractScript.restore_provider_state(provider, StringName(key), flat_state.get(key, {}), errors)
	if fail_loudly:
		_report_errors(errors)
	return errors.is_empty()


func _build_default_entries() -> Array[Dictionary]:
	return [
		_build_autoload_entry(&"game_manager", &"GameManager", SECTION_GAME_MANAGER),
		_build_autoload_entry(&"world_system", &"WorldSystem", SECTION_WORLD_SYSTEM),
		_build_autoload_entry(&"element_database", &"ElementDatabase", SECTION_GLOBAL_SYSTEMS),
		_build_autoload_entry(&"discovery_log", &"DiscoveryLog", SECTION_GLOBAL_SYSTEMS),
		_build_autoload_entry(&"research_objectives", &"ResearchObjectives", SECTION_GLOBAL_SYSTEMS),
		_build_autoload_entry(&"weather_system", &"WeatherSystem", SECTION_GLOBAL_SYSTEMS),
		_build_service_entry(&"power_switchboard", EventBus.SERVICE_POWER_SWITCHBOARD, SECTION_GLOBAL_SYSTEMS),
		_build_service_entry(&"cold_system", EventBus.SERVICE_COLD_SYSTEM, SECTION_GLOBAL_SYSTEMS),
	]


func _build_autoload_entry(key: StringName, autoload_name: StringName, section: StringName) -> Dictionary:
	return {
		"key": key,
		"section": section,
		"provider_type": PROVIDER_TYPE_AUTOLOAD,
		"provider_name": autoload_name,
	}


func _build_service_entry(key: StringName, service_id: StringName, section: StringName) -> Dictionary:
	return {
		"key": key,
		"section": section,
		"provider_type": PROVIDER_TYPE_SERVICE,
		"service_id": service_id,
	}


func _build_empty_sections_from_entries(entries: Array) -> Dictionary:
	var sections := {
		String(SECTION_GAME_MANAGER): {},
		String(SECTION_WORLD_SYSTEM): {},
		String(SECTION_GLOBAL_SYSTEMS): {},
	}
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var section := StringName(str(entry.get("section", "")))
		var key := String(entry.get("key", ""))
		if section == SECTION_GLOBAL_SYSTEMS and not key.is_empty():
			var global_systems := sections.get(String(SECTION_GLOBAL_SYSTEMS), {}) as Dictionary
			global_systems[key] = {}
			sections[String(SECTION_GLOBAL_SYSTEMS)] = global_systems
	return sections


func _assign_section_state(sections: Dictionary, entry: Dictionary, state: Dictionary) -> void:
	var section := StringName(str(entry.get("section", "")))
	var key := String(entry.get("key", ""))
	match section:
		SECTION_GAME_MANAGER:
			sections[String(SECTION_GAME_MANAGER)] = state.duplicate(true)
		SECTION_WORLD_SYSTEM:
			sections[String(SECTION_WORLD_SYSTEM)] = state.duplicate(true)
		SECTION_GLOBAL_SYSTEMS:
			var global_systems := sections.get(String(SECTION_GLOBAL_SYSTEMS), {}) as Dictionary
			global_systems[key] = state.duplicate(true)
			sections[String(SECTION_GLOBAL_SYSTEMS)] = global_systems


func _resolve_provider(entry: Dictionary) -> Object:
	if entry.has("provider") and entry.get("provider") != null:
		return entry.get("provider") as Object
	var provider_type := StringName(str(entry.get("provider_type", "")))
	match provider_type:
		PROVIDER_TYPE_AUTOLOAD:
			var provider_name := String(entry.get("provider_name", ""))
			if provider_name.is_empty():
				return null
			return get_node_or_null("/root/%s" % provider_name)
		PROVIDER_TYPE_SERVICE:
			if EventBus == null:
				return null
			return EventBus.get_service(StringName(str(entry.get("service_id", ""))))
		_:
			return null


func _is_valid_section(section: StringName) -> bool:
	return section == SECTION_GAME_MANAGER or section == SECTION_WORLD_SYSTEM or section == SECTION_GLOBAL_SYSTEMS


func _report_errors(errors: Variant) -> void:
	var messages: Array[String] = []
	if errors is PackedStringArray:
		for entry in (errors as PackedStringArray):
			messages.append(str(entry))
	elif errors is Array:
		for entry in (errors as Array):
			messages.append(str(entry))
	for message in messages:
		push_error(message)
