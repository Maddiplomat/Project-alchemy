extends Node

enum GameState { BOOT, LOGIN, MAIN_MENU, LOADING, PLAYING, PAUSED, GAME_OVER }
enum GameplayPhase { SCAN, EXTRACT, COMBINE, STABILIZE, SURVIVE }
enum SessionMode { OFFLINE, ONLINE }
enum SaveTrigger { MANUAL, AUTO_TIMER, BASE_ENTRY, DISCOVERY_UNLOCK, DEATH }

signal game_state_changed(previous_state: GameState, new_state: GameState)
signal gameplay_phase_changed(previous_phase: GameplayPhase, new_phase: GameplayPhase)
signal session_mode_changed(session_mode: SessionMode)
signal active_save_slot_changed(slot_id: int)
signal save_requested(trigger: SaveTrigger)
signal dirty_state_changed(is_dirty: bool)
signal playtime_changed(playtime_seconds: int)

signal player_health_changed(current_health: int, max_health: int)
signal player_status_effects_changed(status_effects: Array[StringName])
signal player_died
signal pause_changed(is_paused: bool)

signal day_changed(day: int)
signal time_of_day_changed(time_of_day: float)
signal night_started
signal day_started

signal environmental_warning_changed(warning_id: StringName, active: bool)

var game_state: GameState = GameState.BOOT
var gameplay_phase: GameplayPhase = GameplayPhase.SCAN
var session_mode: SessionMode = SessionMode.OFFLINE

var active_save_slot: int = 1
var max_save_slots: int = 3
var is_dirty: bool = false
var playtime_seconds: int = 0
var autosave_interval_seconds: int = 300

var current_day: int = 1
var time_of_day: float = 0.0
var day_length_seconds: float = 900.0
var night_start_time: float = 0.75
var day_start_time: float = 0.25

var max_player_health: int = 100
var player_health: int = 100
var player_status_effects: Array[StringName] = []

var is_paused: bool = false
var active_environmental_warnings: Array[StringName] = []

var _seconds_since_autosave_request: int = 0
var _is_night: bool = false


func _ready() -> void:
	_is_night = _is_time_night(time_of_day)


func start_new_game(mode: SessionMode = SessionMode.OFFLINE, slot_id: int = 1) -> void:
	set_session_mode(mode)
	set_active_save_slot(slot_id)
	current_day = 1
	day_changed.emit(current_day)
	time_of_day = 0.0
	_is_night = _is_time_night(time_of_day)
	time_of_day_changed.emit(time_of_day)
	playtime_seconds = 0
	playtime_changed.emit(playtime_seconds)
	set_gameplay_phase(GameplayPhase.SCAN)
	player_status_effects.clear()
	player_status_effects_changed.emit(player_status_effects.duplicate())
	set_player_health(max_player_health)
	clear_dirty()
	resume_game()
	set_game_state(GameState.PLAYING)


func request_load_game(slot_id: int) -> void:
	set_active_save_slot(slot_id)
	set_game_state(GameState.LOADING)


func request_save(trigger: SaveTrigger = SaveTrigger.MANUAL) -> void:
	_seconds_since_autosave_request = 0
	save_requested.emit(trigger)


func mark_dirty() -> void:
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

	if was_night == _is_night:
		return

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


func set_player_health(value: int) -> void:
	var clamped_health := clampi(value, 0, max_player_health)
	if player_health == clamped_health:
		return

	player_health = clamped_health
	player_health_changed.emit(player_health, max_player_health)
	mark_dirty()

	if player_health <= 0:
		player_died.emit()
		request_save(SaveTrigger.DEATH)
		set_game_state(GameState.GAME_OVER)


func damage_player(amount: int) -> void:
	if amount <= 0:
		return

	set_player_health(player_health - amount)


func heal_player(amount: int) -> void:
	if amount <= 0:
		return

	set_player_health(player_health + amount)


func set_player_status_effects(effects: Array[StringName]) -> void:
	if player_status_effects == effects:
		return

	player_status_effects = effects.duplicate()
	player_status_effects_changed.emit(player_status_effects.duplicate())
	mark_dirty()


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


func _is_time_night(value: float) -> bool:
	if is_equal_approx(night_start_time, day_start_time):
		return false

	if night_start_time > day_start_time:
		return value >= night_start_time or value < day_start_time

	return value >= night_start_time and value < day_start_time
