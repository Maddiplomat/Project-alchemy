extends Node

enum GameState { BOOT, LOGIN, MAIN_MENU, LOADING, PLAYING, PAUSED, GAME_OVER }
enum GameplayPhase { SCAN, EXTRACT, COMBINE, STABILIZE, SURVIVE }
enum SessionMode { OFFLINE, ONLINE }
enum SaveTrigger { MANUAL, AUTO_TIMER, BASE_ENTRY, DISCOVERY_UNLOCK, DEATH }
enum ScannerTier { BASIC, ADVANCED }

signal game_state_changed(previous_state: GameState, new_state: GameState)
signal gameplay_phase_changed(previous_phase: GameplayPhase, new_phase: GameplayPhase)
signal session_mode_changed(session_mode: SessionMode)
signal active_save_slot_changed(slot_id: int)
signal save_requested(trigger: SaveTrigger)
signal dirty_state_changed(is_dirty: bool)
signal playtime_changed(playtime_seconds: int)

signal player_health_changed(current_health: int, max_health: int)
signal player_status_effects_changed(status_effects: Array[StringName])
signal player_died(cause_of_death: StringName)
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
var player_health_system: Node = null
var _health_system: Node = null
var is_player_warmed: bool = false
var cold_level: float = 0.0
const COLD_BUILDUP_RATE: float = 2.0
const COLD_DECAY_RATE: float = 5.0
const COLD_MAX: float = 100.0
const COLD_DAMAGE_TICK_RATE: float = 2.0

var is_paused: bool = false
var active_environmental_warnings: Array[StringName] = []
var scanner_tier: ScannerTier = ScannerTier.BASIC

var _seconds_since_autosave_request: int = 0
var _is_night: bool = false
var _cold_damage_timer: float = 0.0

var _night_canvas_modulate: CanvasModulate = null
var _frost_rect: TextureRect = null

func _ready() -> void:
	_is_night = _is_time_night(time_of_day)
	_setup_night_modulate()
	_setup_frost_overlay()

func _setup_frost_overlay() -> void:
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	
	_frost_rect = TextureRect.new()
	_frost_rect.name = "FrostOverlay"
	_frost_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frost_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frost_rect.modulate = Color(1.0, 1.0, 1.0, 0.0)
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.8, 0.9, 1.0, 0.0))
	gradient.add_point(0.7, Color(0.8, 0.9, 1.0, 0.1))
	gradient.add_point(1.0, Color(0.6, 0.8, 1.0, 0.6))
	
	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 1280
	texture.height = 720
	
	_frost_rect.texture = texture
	canvas_layer.add_child(_frost_rect)
	add_child(canvas_layer)

func _setup_night_modulate() -> void:
	_night_canvas_modulate = CanvasModulate.new()
	_night_canvas_modulate.name = "NightModulate"
	_night_canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(_night_canvas_modulate)
	_update_night_modulate()

func _update_night_modulate() -> void:
	if _night_canvas_modulate == null:
		return
	if _is_night:
		_night_canvas_modulate.color = Color(0.6, 0.6, 0.7, 1.0)
	else:
		_night_canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0)

func is_night() -> bool:
	return _is_night

func _process(delta: float) -> void:
	if game_state == GameState.PLAYING and not is_paused:
		var new_time := _advance_time_of_day(delta)
		set_time_of_day(new_time)
		
	_update_cold_level(delta)

func _update_cold_level(delta: float) -> void:
	if is_player_warmed or not _is_night:
		cold_level = maxf(0.0, cold_level - COLD_DECAY_RATE * delta)
	else:
		cold_level = minf(COLD_MAX, cold_level + COLD_BUILDUP_RATE * delta)
		
	if _frost_rect != null:
		_frost_rect.modulate.a = (cold_level / COLD_MAX) * 0.95
		
	if cold_level >= COLD_MAX and not is_player_warmed:
		_cold_damage_timer += delta
		if _cold_damage_timer >= COLD_DAMAGE_TICK_RATE:
			damage_player(2)
			_cold_damage_timer = 0.0
	else:
		_cold_damage_timer = 0.0


func start_new_game(mode: SessionMode = SessionMode.OFFLINE, slot_id: int = 1) -> void:
	set_session_mode(mode)
	set_active_save_slot(slot_id)
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
	clear_dirty()
	new_game_started.emit()
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

	if was_night != _is_night:
		if _is_night:
			night_started.emit()
		else:
			day_started.emit()
		_update_night_modulate()


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

		var previous_status_effects_changed := Callable(self, "_on_bound_player_status_effects_changed")
		if _health_system.status_effects_changed.is_connected(previous_status_effects_changed):
			_health_system.status_effects_changed.disconnect(previous_status_effects_changed)

	_health_system = system
	player_health_system = system
	if _health_system == null:
		return

	_health_system.health_changed.connect(_on_player_health_changed)
	_health_system.player_died.connect(_on_player_died_from_system)
	_health_system.status_effects_changed.connect(_on_bound_player_status_effects_changed)


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


func _on_player_health_changed(current: int, maximum: int) -> void:
	max_player_health = maximum
	set_player_health(current)


func _on_player_died_from_system(_cause_of_death: StringName = &"unknown") -> void:
	if game_state != GameState.GAME_OVER:
		request_save(SaveTrigger.DEATH)
		set_game_state(GameState.GAME_OVER)


func _on_bound_player_health_changed(current_health: int, maximum_health: int) -> void:
	max_player_health = maximum_health
	_sync_player_health(current_health)


func _on_bound_player_died(cause_of_death: StringName) -> void:
	if game_state == GameState.GAME_OVER:
		return

	request_save(SaveTrigger.DEATH)
	player_died.emit(cause_of_death)
	set_game_state(GameState.GAME_OVER)


func _on_bound_player_status_effects_changed(status_effects: Array[StringName]) -> void:
	set_player_status_effects(status_effects)


func _sync_player_health(value: int) -> void:
	var clamped_health := clampi(value, 0, max_player_health)
	if player_health == clamped_health:
		return

	player_health = clamped_health
	player_health_changed.emit(player_health, max_player_health)
	mark_dirty()


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
