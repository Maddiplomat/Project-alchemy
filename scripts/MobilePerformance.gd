extends Node

signal profile_changed(profile: StringName)

const PROFILE_LOW := &"low"
const PROFILE_BALANCED := &"balanced"
const PROFILE_HIGH := &"high"
const SETTINGS_PATH := "user://mobile_performance.cfg"
const SETTINGS_SECTION := "mobile_performance"
const SETTINGS_KEY_PROFILE := "profile"

var current_profile: StringName = PROFILE_HIGH


func _ready() -> void:
	current_profile = _default_profile()
	_load_profile()
	_apply_profile()


func get_target_fps_minimum() -> int:
	return 60


func get_target_fps_preferred() -> int:
	return 90


func set_profile(profile: StringName) -> void:
	if profile == &"":
		profile = PROFILE_BALANCED
	if current_profile == profile:
		return
	current_profile = profile
	_apply_profile()
	_save_profile()
	profile_changed.emit(current_profile)


func get_profile() -> StringName:
	return current_profile


func get_fps_cap() -> int:
	match current_profile:
		PROFILE_HIGH:
			return get_target_fps_preferred()
		_:
			return get_target_fps_minimum()


func get_particle_amount_scale() -> float:
	match current_profile:
		PROFILE_LOW:
			return 0.45
		PROFILE_BALANCED:
			return 0.7
		_:
			return 1.0


func get_light_energy_scale() -> float:
	match current_profile:
		PROFILE_LOW:
			return 0.75
		PROFILE_BALANCED:
			return 0.88
		_:
			return 1.0


func get_light_texture_size() -> int:
	match current_profile:
		PROFILE_LOW:
			return 96
		PROFILE_BALANCED:
			return 128
		_:
			return 192


func get_hud_poll_interval() -> float:
	match current_profile:
		PROFILE_LOW:
			return 0.18
		PROFILE_BALANCED:
			return 0.12
		_:
			return 0.08


func get_marker_refresh_interval() -> float:
	match current_profile:
		PROFILE_LOW:
			return 0.4
		PROFILE_BALANCED:
			return 0.25
		_:
			return 0.16


func get_world_poll_interval() -> float:
	match current_profile:
		PROFILE_LOW:
			return 0.75
		PROFILE_BALANCED:
			return 0.5
		_:
			return 0.33


func prefers_mobile_profile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _default_profile() -> StringName:
	return PROFILE_BALANCED if prefers_mobile_profile() else PROFILE_HIGH


func _apply_profile() -> void:
	var fps_cap := get_fps_cap()
	Engine.max_fps = fps_cap if fps_cap > 0 else 0


func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var loaded_profile := StringName(str(config.get_value(SETTINGS_SECTION, SETTINGS_KEY_PROFILE, current_profile)))
	if loaded_profile != &"":
		current_profile = loaded_profile


func _save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY_PROFILE, String(current_profile))
	config.save(SETTINGS_PATH)
