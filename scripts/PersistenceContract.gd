extends RefCounted

const METHOD_KEY := &"get_persistence_key"
const METHOD_CAPTURE := &"capture_persistent_state"
const METHOD_RESTORE := &"restore_persistent_state"


static func validate_provider(provider: Object, expected_key: StringName, errors: Array[String]) -> bool:
	if provider == null:
		errors.append("Missing persistence provider for key '%s'." % String(expected_key))
		return false
	if not provider.has_method(METHOD_KEY):
		errors.append("Persistence provider for key '%s' is missing %s()." % [String(expected_key), String(METHOD_KEY)])
		return false
	if not provider.has_method(METHOD_CAPTURE):
		errors.append("Persistence provider for key '%s' is missing %s()." % [String(expected_key), String(METHOD_CAPTURE)])
		return false
	if not provider.has_method(METHOD_RESTORE):
		errors.append("Persistence provider for key '%s' is missing %s()." % [String(expected_key), String(METHOD_RESTORE)])
		return false
	var actual_key_variant: Variant = provider.call(METHOD_KEY)
	var actual_key := StringName(str(actual_key_variant))
	if actual_key.is_empty():
		errors.append("Persistence provider returned an empty persistence key for expected key '%s'." % String(expected_key))
		return false
	if actual_key != expected_key:
		errors.append(
			"Persistence provider key mismatch. Expected '%s', got '%s'."
			% [String(expected_key), String(actual_key)]
		)
		return false
	return true


static func capture_provider_state(provider: Object, expected_key: StringName, errors: Array[String]) -> Dictionary:
	if not validate_provider(provider, expected_key, errors):
		return {}
	var state: Variant = provider.call(METHOD_CAPTURE)
	if not (state is Dictionary):
		errors.append("Persistence provider '%s' returned a non-dictionary state." % String(expected_key))
		return {}
	return (state as Dictionary).duplicate(true)


static func validate_restore_state_shape(state: Variant, expected_key: StringName, errors: Array[String]) -> bool:
	if not (state is Dictionary):
		errors.append("Persistence state for key '%s' must be a dictionary." % String(expected_key))
		return false
	return true


static func restore_provider_state(provider: Object, expected_key: StringName, state: Variant, errors: Array[String]) -> bool:
	if not validate_provider(provider, expected_key, errors):
		return false
	if not validate_restore_state_shape(state, expected_key, errors):
		return false
	provider.call(METHOD_RESTORE, (state as Dictionary).duplicate(true))
	return true
