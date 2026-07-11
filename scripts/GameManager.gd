extends Node

const WorldSaveDataScript = preload("res://scripts/WorldSaveData.gd")

enum GameState { BOOT, LOGIN, MAIN_MENU, LOADING, PLAYING, PAUSED, GAME_OVER }
enum GameplayPhase { SCAN, EXTRACT, COMBINE, STABILIZE, SURVIVE }
enum SessionMode { OFFLINE, ONLINE }
enum SaveTrigger { MANUAL, AUTO_TIMER, BASE_ENTRY, DISCOVERY_UNLOCK, DEATH, QUIT }
enum ScannerTier { BASIC, ADVANCED }

const SAVE_DIRECTORY := "user://saves"
const SAVE_FILE_TEMPLATE := "user://saves/slot_%d.json"
const BACKUP_SAVE_FILE_TEMPLATE := "user://saves/slot_%d.bak.json"
const LEGACY_SAVE_FILE_TEMPLATE := "user://saves/slot_%d.save"
const PERSISTENCE_KEY := &"game_manager"

signal game_state_changed(previous_state: GameState, new_state: GameState)
signal gameplay_phase_changed(previous_phase: GameplayPhase, new_phase: GameplayPhase)
signal session_mode_changed(session_mode: SessionMode)
signal active_save_slot_changed(slot_id: int)
signal save_requested(trigger: SaveTrigger)
signal save_completed(result: Dictionary)
signal dirty_state_changed(is_dirty: bool)
signal playtime_changed(playtime_seconds: int)

signal player_health_changed(current_health: int, max_health: int)
signal player_status_effects_changed(status_effects: Array[StringName])
signal player_died(cause_of_death: StringName)
signal player_registered(player: Node2D)
signal player_unregistered(player: Node2D)
signal pause_changed(is_paused: bool)

signal day_changed(day: int)
signal time_of_day_changed(time_of_day: float)
signal night_started
signal day_started
signal new_game_started

signal environmental_warning_changed(warning_id: StringName, active: bool)
signal scanner_tier_changed(previous_tier: ScannerTier, new_tier: ScannerTier)

var game_state: GameState = GameState.BOOT
var gameplay_phase: GameplayPhase = GameplayPhase.SCAN
var session_mode: SessionMode = SessionMode.OFFLINE

var active_save_slot: int = 1
var max_save_slots: int = 3
var is_dirty: bool = false
var playtime_seconds: int = 0
var autosave_interval_seconds: int = 300

var current_day: int = 1
var time_of_day: float = 0.25
var day_duration_seconds: float = 450.0
var night_duration_seconds: float = 300.0
var night_start_time: float = 0.75
var day_start_time: float = 0.25

var max_player_health: int = 100
var player_health: int = 100
var player_status_effects: Array[StringName] = []
var player: Node2D = null
var player_health_system: Node = null
var _health_system: Node = null

var is_paused: bool = false
var active_environmental_warnings: Array[StringName] = []
var scanner_tier: ScannerTier = ScannerTier.BASIC
var post_tutorial_loop_active := false
var tutorial_hint_flags: Dictionary[StringName, bool] = {}

var _seconds_since_autosave_request: int = 0
var _is_night: bool = false
var _playtime_accumulator := 0.0
var _automatic_saves_enabled := false
var last_save_result: Dictionary = {}

func _ready() -> void:
	_is_night = _is_time_night(time_of_day)
	if not save_requested.is_connected(_on_save_requested):
		save_requested.connect(_on_save_requested)
	if ResearchObjectives != null and ResearchObjectives.has_signal("objective_completed"):
		if not ResearchObjectives.objective_completed.is_connected(_on_objective_completed):
			ResearchObjectives.objective_completed.connect(_on_objective_completed)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if game_state != GameState.BOOT and game_state != GameState.MAIN_MENU:
		request_save(SaveTrigger.QUIT)
	get_tree().quit()

func is_night() -> bool:
	return _is_night


func get_persistence_key() -> StringName:
	return PERSISTENCE_KEY


func register_player(player_node: Node2D) -> void:
	if player_node == null:
		return
	if player == player_node:
		return
	player = player_node
	player_registered.emit(player_node)


func unregister_player(player_node: Node2D) -> void:
	if player != player_node:
		return
	player = null
	player_unregistered.emit(player_node)


func get_player() -> Node2D:
	if player != null and is_instance_valid(player):
		return player
	player = null
	return null


func get_player_world_position() -> Variant:
	var current_player := get_player()
	if current_player == null:
		return null
	return current_player.global_position


func set_player_warmed(value: bool) -> void:
	var cold_system := EventBus.get_cold_system()
	if cold_system != null and cold_system.has_method("set_player_warmed"):
		cold_system.set_player_warmed(value)


func get_player_warmed() -> bool:
	var cold_system := EventBus.get_cold_system()
	if cold_system != null and cold_system.has_method("is_warmed"):
		return bool(cold_system.is_warmed())
	return false


func get_cold_level() -> float:
	var cold_system := EventBus.get_cold_system()
	if cold_system != null and cold_system.has_method("get_cold_level"):
		return float(cold_system.get_cold_level())
	return 0.0


func reset_temperature_state() -> void:
	var cold_system := EventBus.get_cold_system()
	if cold_system != null and cold_system.has_method("reset_state"):
		cold_system.reset_state()

func _process(delta: float) -> void:
	if game_state == GameState.PLAYING and not is_paused:
		var new_time := _advance_time_of_day(delta)
		set_time_of_day(new_time)
		_playtime_accumulator += maxf(delta, 0.0)
		var whole_seconds := int(floor(_playtime_accumulator))
		if whole_seconds > 0:
			_playtime_accumulator -= float(whole_seconds)
			add_playtime(whole_seconds)


func _input(event: InputEvent) -> void:
	if not _is_manual_save_input(event):
		return
	if game_state != GameState.PLAYING:
		return
	request_save(SaveTrigger.MANUAL)
	get_viewport().set_input_as_handled()


func _is_manual_save_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.echo or not key_event.pressed:
			return false
		if key_event.keycode == KEY_F6 or key_event.physical_keycode == KEY_F6:
			return true
		if key_event.keycode == KEY_S and (key_event.meta_pressed or key_event.ctrl_pressed):
			return true
	return event.is_action_pressed("manual_save")


func start_new_game(mode: SessionMode = SessionMode.OFFLINE, slot_id: int = 1) -> void:
	set_session_mode(mode)
	set_active_save_slot(slot_id)
	_automatic_saves_enabled = false
	post_tutorial_loop_active = false
	tutorial_hint_flags.clear()
	if InventoryManager != null and InventoryManager.has_method("clear_inventory"):
		InventoryManager.clear_inventory()
	if DiscoveryLog != null and DiscoveryLog.has_method("clear"):
		DiscoveryLog.clear()
	if DiscoveryJournal != null and DiscoveryJournal.has_method("clear"):
		DiscoveryJournal.clear()
	if ElementDatabase != null:
		ElementDatabase.clear_scanned_elements()
	if RecipeDatabase != null and RecipeDatabase.has_method("reset_runtime_state"):
		RecipeDatabase.reset_runtime_state()
	if ResearchObjectives != null and ResearchObjectives.has_method("reset_for_new_game"):
		ResearchObjectives.reset_for_new_game()
	current_day = 1
	day_changed.emit(current_day)
	time_of_day = day_start_time
	_is_night = _is_time_night(time_of_day)
	time_of_day_changed.emit(time_of_day)
	playtime_seconds = 0
	playtime_changed.emit(playtime_seconds)
	set_scanner_tier(ScannerTier.BASIC)
	set_gameplay_phase(GameplayPhase.SCAN)
	reset_player_state()
	reset_temperature_state()
	clear_dirty()
	new_game_started.emit()
	var was_paused := is_paused or get_tree().paused
	is_paused = false
	get_tree().paused = false
	if was_paused:
		pause_changed.emit(is_paused)
	set_game_state(GameState.PLAYING)


func request_load_game(slot_id: int) -> void:
	set_active_save_slot(slot_id)
	if not has_save_data(slot_id):
		return
	set_game_state(GameState.LOADING)
	_load_game_from_slot(slot_id)


func request_save(trigger: SaveTrigger = SaveTrigger.MANUAL) -> Dictionary:
	if _is_automatic_save_trigger(trigger) and not _automatic_saves_enabled:
		return _set_save_result({
			&"success": false,
			&"trigger": trigger,
			&"slot_id": active_save_slot,
			&"path": _get_save_file_path(active_save_slot),
			&"absolute_path": ProjectSettings.globalize_path(_get_save_file_path(active_save_slot)),
			&"error": "Automatic saves are disabled until this session is manually saved or loaded.",
			&"skipped": true,
		})
	_seconds_since_autosave_request = 0
	var world_save_data := EventBus.get_world_save_data()
	if world_save_data != null and world_save_data.has_method("sync_runtime_state"):
		world_save_data.sync_runtime_state()
	save_requested.emit(trigger)
	return last_save_result.duplicate(true)


func has_save_data(slot_id: int = active_save_slot) -> bool:
	return FileAccess.file_exists(_get_save_file_path(slot_id)) \
		or FileAccess.file_exists(_get_legacy_save_file_path(slot_id))


func get_save_metadata(slot_id: int = active_save_slot) -> Dictionary:
	if not has_save_data(slot_id):
		return {}
	var save_data := _read_normalized_save_envelope(slot_id, true)
	if save_data.is_empty():
		return {}
	return (save_data.get("metadata", {}) as Dictionary).duplicate(true)


func has_any_save_data() -> bool:
	for slot_id in range(1, max_save_slots + 1):
		if has_save_data(slot_id):
			return true
	return false


func get_continue_slot() -> int:
	var best_slot := -1
	var best_saved_at := -1
	for slot_id in range(1, max_save_slots + 1):
		var metadata := get_save_metadata(slot_id)
		if metadata.is_empty():
			continue
		var saved_at_unix := int(metadata.get("saved_at_unix", 0))
		if saved_at_unix > best_saved_at:
			best_saved_at = saved_at_unix
			best_slot = slot_id
	if best_slot != -1:
		return best_slot
	return active_save_slot if has_save_data(active_save_slot) else -1


func mark_dirty() -> void:
	var world_save_data := EventBus.get_world_save_data()
	if world_save_data != null and world_save_data.has_method("sync_runtime_state"):
		world_save_data.sync_runtime_state()
	if is_dirty:
		return

	is_dirty = true
	dirty_state_changed.emit(is_dirty)


func clear_dirty() -> void:
	if not is_dirty:
		_seconds_since_autosave_request = 0
		return

	is_dirty = false
	_seconds_since_autosave_request = 0
	dirty_state_changed.emit(is_dirty)


func set_game_state(new_state: GameState) -> void:
	if game_state == new_state:
		return

	var previous_state := game_state
	game_state = new_state
	game_state_changed.emit(previous_state, game_state)


func set_gameplay_phase(new_phase: GameplayPhase) -> void:
	if gameplay_phase == new_phase:
		return

	var previous_phase := gameplay_phase
	gameplay_phase = new_phase
	gameplay_phase_changed.emit(previous_phase, gameplay_phase)


func set_session_mode(new_mode: SessionMode) -> void:
	if session_mode == new_mode:
		return

	session_mode = new_mode
	session_mode_changed.emit(session_mode)


func set_active_save_slot(slot_id: int) -> void:
	var clamped_slot := clampi(slot_id, 1, max_save_slots)
	if active_save_slot == clamped_slot:
		return

	active_save_slot = clamped_slot
	active_save_slot_changed.emit(active_save_slot)


func pause_game() -> void:
	if is_paused:
		return

	is_paused = true
	get_tree().paused = true
	pause_changed.emit(is_paused)
	set_game_state(GameState.PAUSED)


func resume_game() -> void:
	if not is_paused:
		return

	is_paused = false
	get_tree().paused = false
	pause_changed.emit(is_paused)
	if game_state == GameState.PAUSED:
		set_game_state(GameState.PLAYING)


func toggle_pause() -> void:
	if is_paused:
		resume_game()
	else:
		pause_game()


func advance_day() -> void:
	current_day += 1
	day_changed.emit(current_day)
	mark_dirty()


func set_time_of_day(value: float) -> void:
	var clamped_time := clampf(value, 0.0, 1.0)
	if is_equal_approx(time_of_day, clamped_time):
		return

	var was_night := _is_night
	time_of_day = clamped_time
	_is_night = _is_time_night(time_of_day)
	time_of_day_changed.emit(time_of_day)
	mark_dirty()

	if was_night != _is_night:
		if _is_night:
			night_started.emit()
		else:
			day_started.emit()


func add_playtime(seconds: int) -> void:
	if seconds <= 0:
		return

	playtime_seconds += seconds
	playtime_changed.emit(playtime_seconds)

	if not is_dirty:
		return

	_seconds_since_autosave_request += seconds
	if _seconds_since_autosave_request >= autosave_interval_seconds:
		request_save(SaveTrigger.AUTO_TIMER)


func set_player_health(value: int, cause_of_death: StringName = &"unknown") -> void:
	var clamped_health := clampi(value, 0, max_player_health)
	if player_health == clamped_health:
		return

	player_health = clamped_health
	player_health_changed.emit(player_health, max_player_health)
	mark_dirty()

	if player_health <= 0:
		player_died.emit(cause_of_death)
		request_save(SaveTrigger.DEATH)
		set_game_state(GameState.GAME_OVER)


func damage_player(amount: int) -> void:
	if amount <= 0:
		return

	if player_health_system != null and player_health_system.has_method("take_damage"):
		player_health_system.take_damage(amount, &"physical")
		return

	set_player_health(player_health - amount, &"physical")


func heal_player(amount: int) -> void:
	if amount <= 0:
		return

	if player_health_system != null and player_health_system.has_method("heal"):
		player_health_system.heal(amount)
		return

	set_player_health(player_health + amount)


func set_player_status_effects(effects: Array[StringName]) -> void:
	if player_status_effects == effects:
		return

	player_status_effects = effects.duplicate()
	player_status_effects_changed.emit(player_status_effects.duplicate())
	mark_dirty()


func bind_player_health_system(system: Node) -> void:
	if _health_system == system:
		return

	if _health_system != null:
		var previous_health_changed := Callable(self, "_on_player_health_changed")
		if _health_system.health_changed.is_connected(previous_health_changed):
			_health_system.health_changed.disconnect(previous_health_changed)

		var previous_player_died := Callable(self, "_on_player_died_from_system")
		if _health_system.player_died.is_connected(previous_player_died):
			_health_system.player_died.disconnect(previous_player_died)

		var previous_status_effects_changed := Callable(self, "_on_player_status_effects_changed_from_system")
		if _health_system.status_effects_changed.is_connected(previous_status_effects_changed):
			_health_system.status_effects_changed.disconnect(previous_status_effects_changed)

	_health_system = system
	player_health_system = system
	if _health_system == null:
		return

	_health_system.health_changed.connect(_on_player_health_changed)
	_health_system.player_died.connect(_on_player_died_from_system)
	_health_system.status_effects_changed.connect(_on_player_status_effects_changed_from_system)


func reset_player_state() -> void:
	if player_health_system != null and player_health_system.has_method("reset_state"):
		player_health_system.reset_state()
		return

	player_status_effects.clear()
	player_status_effects_changed.emit(player_status_effects.duplicate())
	set_player_health(max_player_health)


func set_environmental_warning(warning_id: StringName, active: bool) -> void:
	if warning_id.is_empty():
		return

	var warning_index := active_environmental_warnings.find(warning_id)
	if active and warning_index == -1:
		active_environmental_warnings.append(warning_id)
		environmental_warning_changed.emit(warning_id, true)
		return

	if not active and warning_index != -1:
		active_environmental_warnings.remove_at(warning_index)
		environmental_warning_changed.emit(warning_id, false)


func set_scanner_tier(new_tier: ScannerTier) -> void:
	_set_scanner_tier_internal(new_tier, true, true)


func restore_scanner_tier(new_tier: ScannerTier) -> void:
	_set_scanner_tier_internal(new_tier, false, false)


func _set_scanner_tier_internal(new_tier: ScannerTier, should_mark_dirty: bool, should_emit_signal: bool) -> void:
	if scanner_tier == new_tier:
		return

	var previous_tier := scanner_tier
	scanner_tier = new_tier
	if should_emit_signal:
		scanner_tier_changed.emit(previous_tier, scanner_tier)
	if should_mark_dirty:
		mark_dirty()


func unlock_advanced_scanner() -> void:
	set_scanner_tier(ScannerTier.ADVANCED)


func has_advanced_scanner() -> bool:
	return scanner_tier == ScannerTier.ADVANCED


func has_seen_tutorial_hint(hint_id: StringName) -> bool:
	if hint_id.is_empty():
		return false
	return bool(tutorial_hint_flags.get(hint_id, false))


func mark_tutorial_hint_seen(hint_id: StringName) -> void:
	if hint_id.is_empty() or has_seen_tutorial_hint(hint_id):
		return
	tutorial_hint_flags[hint_id] = true
	mark_dirty()


func capture_persistent_state() -> Dictionary:
	return {
		"session_mode": int(session_mode),
		"active_save_slot": active_save_slot,
		"current_day": current_day,
		"time_of_day": time_of_day,
		"playtime_seconds": playtime_seconds,
		"scanner_tier": int(scanner_tier),
		"post_tutorial_loop_active": post_tutorial_loop_active,
		"tutorial_hint_flags": tutorial_hint_flags.duplicate(true),
	}


func restore_persistent_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	session_mode = int(data.get("session_mode", int(SessionMode.OFFLINE)))
	active_save_slot = clampi(int(data.get("active_save_slot", active_save_slot)), 1, max_save_slots)
	current_day = maxi(int(data.get("current_day", 1)), 1)
	time_of_day = clampf(float(data.get("time_of_day", day_start_time)), 0.0, 1.0)
	_is_night = _is_time_night(time_of_day)
	playtime_seconds = maxi(int(data.get("playtime_seconds", 0)), 0)
	post_tutorial_loop_active = bool(data.get("post_tutorial_loop_active", false))
	tutorial_hint_flags.clear()
	var raw_tutorial_flags: Variant = data.get("tutorial_hint_flags", {})
	if raw_tutorial_flags is Dictionary:
		for raw_hint_id: Variant in (raw_tutorial_flags as Dictionary).keys():
			tutorial_hint_flags[StringName(str(raw_hint_id))] = bool(raw_tutorial_flags[raw_hint_id])
	_set_scanner_tier_internal(int(data.get("scanner_tier", int(ScannerTier.BASIC))), false, false)
	is_paused = false
	get_tree().paused = false
	active_environmental_warnings.clear()
	_playtime_accumulator = 0.0
	day_changed.emit(current_day)
	time_of_day_changed.emit(time_of_day)
	playtime_changed.emit(playtime_seconds)
	pause_changed.emit(false)
	clear_dirty()


func restore_player_runtime_state(health: int, effects: Array[StringName], maximum_health: int = max_player_health) -> void:
	max_player_health = maxi(maximum_health, 1)
	player_health = clampi(health, 0, max_player_health)
	player_status_effects = effects.duplicate()
	player_health_changed.emit(player_health, max_player_health)
	player_status_effects_changed.emit(player_status_effects.duplicate())


func finish_load_game() -> void:
	_automatic_saves_enabled = true
	if is_paused:
		is_paused = false
		get_tree().paused = false
		pause_changed.emit(false)
	set_game_state(GameState.PLAYING)
	clear_dirty()


func _on_player_health_changed(current: int, maximum: int) -> void:
	max_player_health = maximum
	set_player_health(current)


func _on_player_died_from_system(_cause_of_death: StringName = &"unknown") -> void:
	if game_state != GameState.GAME_OVER:
		request_save(SaveTrigger.DEATH)
		set_game_state(GameState.GAME_OVER)


func _on_player_status_effects_changed_from_system(status_effects: Array[StringName]) -> void:
	set_player_status_effects(status_effects)


func _on_objective_completed(objective_id: StringName) -> void:
	if objective_id == &"power_defenses":
		post_tutorial_loop_active = true


func _on_save_requested(_trigger: SaveTrigger) -> void:
	var world_save_data := EventBus.get_world_save_data()
	if world_save_data == null or not world_save_data.has_method("capture_runtime_state"):
		_set_save_result({
			&"success": false,
			&"trigger": _trigger,
			&"slot_id": active_save_slot,
			&"path": _get_save_file_path(active_save_slot),
			&"absolute_path": ProjectSettings.globalize_path(_get_save_file_path(active_save_slot)),
			&"error": "WorldSaveData service is unavailable.",
		})
		return
	var save_data: Dictionary = world_save_data.capture_runtime_state()
	if save_data.is_empty():
		_set_save_result({
			&"success": false,
			&"trigger": _trigger,
			&"slot_id": active_save_slot,
			&"path": _get_save_file_path(active_save_slot),
			&"absolute_path": ProjectSettings.globalize_path(_get_save_file_path(active_save_slot)),
			&"error": "WorldSaveData produced an empty save payload.",
		})
		return
	var save_directory_path := ProjectSettings.globalize_path(SAVE_DIRECTORY)
	if not DirAccess.dir_exists_absolute(save_directory_path):
		var dir_error := DirAccess.make_dir_recursive_absolute(save_directory_path)
		if dir_error != OK:
			var directory_error := "Failed to create save directory: %s (%s)" % [SAVE_DIRECTORY, save_directory_path]
			push_warning(directory_error)
			_set_save_result({
				&"success": false,
				&"trigger": _trigger,
				&"slot_id": active_save_slot,
				&"path": _get_save_file_path(active_save_slot),
				&"absolute_path": ProjectSettings.globalize_path(_get_save_file_path(active_save_slot)),
				&"error": directory_error,
				&"error_code": dir_error,
			})
			return
	_write_backup_save_file(active_save_slot)
	var save_path := _get_save_file_path(active_save_slot)
	var absolute_save_path := ProjectSettings.globalize_path(save_path)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		var file_error_code := FileAccess.get_open_error()
		var file_error := "Failed to open save file for writing: %s (%s)" % [save_path, absolute_save_path]
		push_warning(file_error)
		_set_save_result({
			&"success": false,
			&"trigger": _trigger,
			&"slot_id": active_save_slot,
			&"path": save_path,
			&"absolute_path": absolute_save_path,
			&"error": file_error,
			&"error_code": file_error_code,
		})
		return
	file.store_string(_stringify_save_data_for_storage(save_data, "\t"))
	file.close()
	if _trigger == SaveTrigger.MANUAL:
		_automatic_saves_enabled = true
	clear_dirty()
	_set_save_result({
		&"success": true,
		&"trigger": _trigger,
		&"slot_id": active_save_slot,
		&"path": save_path,
		&"absolute_path": absolute_save_path,
		&"error": "",
		&"saved_at_unix": Time.get_unix_time_from_system(),
	})


func _load_game_from_slot(slot_id: int) -> void:
	var normalized_save_data := _read_normalized_save_envelope(slot_id, true)
	var save_data := _extract_world_save_data(normalized_save_data)
	if save_data.is_empty():
		push_warning("Save payload is invalid for slot %d" % slot_id)
		set_game_state(GameState.MAIN_MENU)
		return
	var current_scene_path := str((normalized_save_data.get("metadata", {}) as Dictionary).get("current_scene_path", "res://scenes/World.tscn"))
	var world_data := save_data.get("world", {}) as Dictionary
	if WorldSystem != null and WorldSystem.has_method("set_seed_for_scene") and not world_data.is_empty():
		var saved_seed := str(world_data.get("seed", ""))
		if not saved_seed.is_empty():
			WorldSystem.set_seed_for_scene(current_scene_path, int(saved_seed))
	if WorldSystem != null and WorldSystem.has_method("queue_pending_restore_state"):
		WorldSystem.queue_pending_restore_state(save_data, {
			&"skip_post_restore_save": true,
			&"source": &"load_game",
		})
	var scene_error := get_tree().change_scene_to_file(current_scene_path)
	if scene_error != OK:
		push_warning("Failed to change scene while loading save slot %d" % slot_id)
		set_game_state(GameState.MAIN_MENU)


func _get_save_file_path(slot_id: int) -> String:
	return SAVE_FILE_TEMPLATE % clampi(slot_id, 1, max_save_slots)


func _get_backup_save_file_path(slot_id: int) -> String:
	return BACKUP_SAVE_FILE_TEMPLATE % clampi(slot_id, 1, max_save_slots)


func _get_legacy_save_file_path(slot_id: int) -> String:
	return LEGACY_SAVE_FILE_TEMPLATE % clampi(slot_id, 1, max_save_slots)


func _write_backup_save_file(slot_id: int) -> void:
	var source_path := _get_save_file_path(slot_id)
	if not FileAccess.file_exists(source_path):
		return
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return
	var source_text := source_file.get_as_text()
	source_file.close()
	var backup_file := FileAccess.open(_get_backup_save_file_path(slot_id), FileAccess.WRITE)
	if backup_file == null:
		return
	backup_file.store_string(source_text)
	backup_file.close()


func _set_save_result(result: Dictionary) -> Dictionary:
	last_save_result = result.duplicate(true)
	save_completed.emit(last_save_result.duplicate(true))
	return last_save_result.duplicate(true)


func _read_save_file(slot_id: int) -> Dictionary:
	var json_path := _get_save_file_path(slot_id)
	if FileAccess.file_exists(json_path):
		return _read_json_save_file(json_path)
	var legacy_path := _get_legacy_save_file_path(slot_id)
	if FileAccess.file_exists(legacy_path):
		return _read_legacy_save_file(legacy_path)
	return {}


func _read_json_save_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw_text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed == null:
		return {}
	var restored: Variant = _decode_save_data_from_storage(parsed)
	return restored as Dictionary if restored is Dictionary else {}


func _read_normalized_save_envelope(slot_id: int, rewrite_if_needed: bool = false) -> Dictionary:
	var raw_save_data := _read_save_file(slot_id)
	if raw_save_data.is_empty():
		return {}
	var normalized_save_data := _normalize_save_envelope(raw_save_data)
	if rewrite_if_needed and _save_envelope_requires_rewrite(raw_save_data, normalized_save_data):
		_write_normalized_save_envelope(slot_id, normalized_save_data)
	return normalized_save_data


func _read_legacy_save_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var payload: Variant = file.get_var()
	file.close()
	return payload as Dictionary if payload is Dictionary else {}


func _extract_world_save_data(save_data: Dictionary) -> Dictionary:
	return _with_world_save_data_codec(func(world_save_data: Node) -> Dictionary:
		if world_save_data == null or not world_save_data.has_method("build_restore_payload"):
			return {}
		return world_save_data.build_restore_payload(save_data)
	)


func _normalize_save_envelope(save_data: Dictionary) -> Dictionary:
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
	return _stringify_save_data_for_storage(raw_save_data) != _stringify_save_data_for_storage(normalized_save_data)


func _write_normalized_save_envelope(slot_id: int, normalized_save_data: Dictionary) -> void:
	var save_path := _get_save_file_path(slot_id)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(_stringify_save_data_for_storage(normalized_save_data, "\t"))
	file.close()


func _with_world_save_data_codec(callback: Callable) -> Variant:
	var world_save_data: Node = EventBus.get_world_save_data()
	var owns_temporary_world_save_data := false
	if world_save_data == null:
		world_save_data = WorldSaveDataScript.new()
		owns_temporary_world_save_data = true
	var result: Variant = callback.call(world_save_data)
	if owns_temporary_world_save_data and is_instance_valid(world_save_data):
		world_save_data.free()
	return result


func _stringify_save_data_for_storage(save_data: Dictionary, indent: String = "") -> String:
	return str(_with_world_save_data_codec(func(world_save_data: Node) -> String:
		if world_save_data != null and world_save_data.has_method("stringify_save_data"):
			return String(world_save_data.stringify_save_data(save_data, indent))
		return JSON.stringify(_variant_to_json_value(save_data), indent)
	))


func _decode_save_data_from_storage(value: Variant) -> Variant:
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
			return {
				"__type": "StringName",
				"value": str(value),
			}
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
			return {
				"__type": "Vector2",
				"x": vector2.x,
				"y": vector2.y,
			}
		TYPE_VECTOR2I:
			var vector2i := value as Vector2i
			return {
				"__type": "Vector2i",
				"x": vector2i.x,
				"y": vector2i.y,
			}
		_:
			return {
				"__type": "VariantString",
				"value": var_to_str(value),
			}


func _json_value_to_variant(value: Variant) -> Variant:
	if value is Array:
		var restored_array: Array = []
		for item in value:
			restored_array.append(_json_value_to_variant(item))
		return restored_array
	if not (value is Dictionary):
		return value
	var value_dict := value as Dictionary
	var type_name := str(value_dict.get("__type", ""))
	match type_name:
		"StringName":
			return StringName(str(value_dict.get("value", "")))
		"Vector2":
			return Vector2(
				float(value_dict.get("x", 0.0)),
				float(value_dict.get("y", 0.0))
			)
		"Vector2i":
			return Vector2i(
				int(value_dict.get("x", 0)),
				int(value_dict.get("y", 0))
			)
		"VariantString":
			return str_to_var(str(value_dict.get("value", "")))
		_:
			var restored_dict := {}
			for raw_key in value_dict.keys():
				restored_dict[raw_key] = _json_value_to_variant(value_dict[raw_key])
			return restored_dict


func _is_time_night(value: float) -> bool:
	if is_equal_approx(night_start_time, day_start_time):
		return false

	if night_start_time > day_start_time:
		return value >= night_start_time or value < day_start_time

	return value >= night_start_time and value < day_start_time


func _advance_time_of_day(delta: float) -> float:
	var current_time := time_of_day
	var remaining_delta := maxf(delta, 0.0)

	while remaining_delta > 0.0:
		if _is_time_night(current_time):
			var seconds_per_cycle_unit := _get_night_seconds_per_cycle_unit()
			var segment_end := day_start_time
			var distance_to_boundary := _distance_to_cycle_boundary(current_time, segment_end)
			var segment_seconds_remaining := distance_to_boundary * seconds_per_cycle_unit
			if remaining_delta >= segment_seconds_remaining and segment_seconds_remaining > 0.0:
				current_time = segment_end
				remaining_delta -= segment_seconds_remaining
				continue
			current_time = wrapf(current_time + (remaining_delta / seconds_per_cycle_unit), 0.0, 1.0)
			remaining_delta = 0.0
		else:
			var seconds_per_cycle_unit := _get_day_seconds_per_cycle_unit()
			var segment_end := night_start_time
			var distance_to_boundary := _distance_to_cycle_boundary(current_time, segment_end)
			var segment_seconds_remaining := distance_to_boundary * seconds_per_cycle_unit
			if remaining_delta >= segment_seconds_remaining and segment_seconds_remaining > 0.0:
				current_time = segment_end
				remaining_delta -= segment_seconds_remaining
				continue
			current_time = wrapf(current_time + (remaining_delta / seconds_per_cycle_unit), 0.0, 1.0)
			remaining_delta = 0.0

	if current_time >= 1.0:
		current_time -= 1.0

	if current_time < time_of_day:
		advance_day()

	return current_time


func _is_automatic_save_trigger(trigger: SaveTrigger) -> bool:
	return trigger != SaveTrigger.MANUAL


func _get_day_seconds_per_cycle_unit() -> float:
	var day_span := _distance_to_cycle_boundary(day_start_time, night_start_time)
	if day_span <= 0.0:
		return maxf(day_duration_seconds, 1.0)
	return maxf(day_duration_seconds, 1.0) / day_span


func _get_night_seconds_per_cycle_unit() -> float:
	var night_span := _distance_to_cycle_boundary(night_start_time, day_start_time)
	if night_span <= 0.0:
		return maxf(night_duration_seconds, 1.0)
	return maxf(night_duration_seconds, 1.0) / night_span


func _distance_to_cycle_boundary(from_time: float, to_time: float) -> float:
	var distance := to_time - from_time
	if distance < 0.0:
		distance += 1.0
	return distance


func _get_player_world_position() -> Variant:
	return get_player_world_position()
