extends Node

enum WeatherState { CLEAR, RAIN, ACID_MIST, ELECTRICAL_STORM }

signal weather_changed(new_state: int)
signal weather_tick(state: int, delta: float)
signal weather_forecast_changed(next_state: int, seconds_until_change: float)
signal weather_warning_started(target_state: int, seconds_remaining: float)
signal weather_warning_ended(target_state: int)

const RAIN_WARNING_ID := &"rain"
const ACID_MIST_WARNING_ID := &"acid_mist"
const ELECTRICAL_STORM_WARNING_ID := &"electrical_storm"
const SULFUR_FLATS_UNLOCK_ENTRY_ID := &"sulfur_flats_weather_unlocked"
const SULFUR_FLATS_UNLOCK_TITLE := "Weather Shift Logged"
const SULFUR_FLATS_UNLOCK_NOTES := "Sulfur Flats exposure has destabilized the weather. Acid Mist and Electrical Storms can now form."

const CLEAR_DURATION_RANGE := Vector2(150.0, 300.0)
const RAIN_DURATION_RANGE := Vector2(90.0, 240.0)
const ACID_MIST_DURATION_RANGE := Vector2(90.0, 180.0)
const ELECTRICAL_STORM_DURATION_RANGE := Vector2(90.0, 150.0)
const WARNING_LEAD_TIME_RANGE := Vector2(10.0, 20.0)
const WEATHER_VISUALS_SCENE := preload("res://scenes/WeatherVisuals.tscn")
const MIN_RAIN_EMISSION_HALF_WIDTH := 460.0
const RAIN_WORLD_MARGIN := 96.0
const RAIN_PARTICLE_FALL_SPEED := 520.0

var current_state: int = WeatherState.CLEAR

var _rng := RandomNumberGenerator.new()
var _state_time_remaining := 0.0
var _rare_weather_unlocked := false
var _night_rain_bonus := 0.0
var _next_state: int = WeatherState.CLEAR
var _warning_lead_time := -1.0
var _warning_active := false
var _weather_visual_root: Node2D = null
var _rain_particles: GPUParticles2D = null


func _ready() -> void:
	_rng.randomize()
	GameManager.time_of_day_changed.connect(_on_time_of_day_changed)
	if GameManager.has_signal("new_game_started"):
		GameManager.new_game_started.connect(_on_new_game_started)
	if GameManager.has_signal("game_state_changed"):
		GameManager.game_state_changed.connect(_on_game_state_changed)
	_refresh_saved_unlock_state()
	_on_time_of_day_changed(GameManager.time_of_day)
	_state_time_remaining = _roll_state_duration(WeatherState.CLEAR)
	_plan_next_state()
	_apply_environmental_warnings()


func _physics_process(delta: float) -> void:
	_sync_weather_visuals()
	if not _is_weather_active():
		return

	_refresh_saved_unlock_state()
	_check_sulfur_flats_unlock()

	_state_time_remaining -= maxf(delta, 0.0)
	_update_transition_warning()
	if _state_time_remaining <= 0.0:
		_transition_to_next_state()

	weather_tick.emit(current_state, delta)


func get_current_state() -> int:
	return current_state


func is_raining() -> bool:
	return current_state == WeatherState.RAIN


func get_state_time_remaining() -> float:
	return maxf(_state_time_remaining, 0.0)


func get_next_state() -> int:
	return _next_state


func is_transition_warning_active() -> bool:
	return _warning_active


func get_transition_warning_state() -> int:
	return _next_state if _warning_active else WeatherState.CLEAR


func get_transition_warning_seconds_remaining() -> float:
	return maxf(_state_time_remaining, 0.0) if _warning_active else -1.0


func get_shelter_at(world_pos: Vector2) -> bool:
	var tile_coords: Variant = _get_world_tile_coords(world_pos)
	if tile_coords == null:
		return false

	for node in get_tree().get_nodes_in_group(&"shelter_roof"):
		if node != null and node.has_method("covers_tile"):
			if bool(node.call("covers_tile", tile_coords)):
				return true
	return false


func has_rare_weather_unlocked() -> bool:
	return _rare_weather_unlocked


func restore_rare_weather_unlock(unlocked: bool) -> void:
	_rare_weather_unlocked = unlocked


func _on_new_game_started() -> void:
	_rare_weather_unlocked = false
	_set_state(WeatherState.CLEAR, true)


func _on_game_state_changed(_previous_state: int, new_state: int) -> void:
	if new_state == GameManager.GameState.MAIN_MENU or new_state == GameManager.GameState.LOADING:
		_set_state(WeatherState.CLEAR, false)


func _on_time_of_day_changed(_time_of_day: float) -> void:
	if GameManager.has_method("is_night") and GameManager.is_night():
		_night_rain_bonus = 0.28 if GameManager.current_day >= 3 else 0.10
	else:
		_night_rain_bonus = 0.0


func _transition_to_next_state() -> void:
	_set_state(_next_state, true)


func _set_state(new_state: int, emit_change: bool) -> void:
	var changed := current_state != new_state
	_clear_transition_warning()
	current_state = new_state
	_state_time_remaining = _roll_state_duration(current_state)
	_plan_next_state()
	_apply_environmental_warnings()
	_sync_weather_visuals()
	if emit_change and changed:
		weather_changed.emit(current_state)


func _roll_state_duration(state: int) -> float:
	var duration_range := CLEAR_DURATION_RANGE
	match state:
		WeatherState.RAIN:
			duration_range = RAIN_DURATION_RANGE
		WeatherState.ACID_MIST:
			duration_range = ACID_MIST_DURATION_RANGE
		WeatherState.ELECTRICAL_STORM:
			duration_range = ELECTRICAL_STORM_DURATION_RANGE
	return _rng.randf_range(duration_range.x, duration_range.y)


func _pick_next_state() -> int:
	var candidates := _build_state_candidates()
	var positive_candidates := 0
	for candidate: Dictionary in candidates:
		if float(candidate.get(&"weight", 0.0)) > 0.0:
			positive_candidates += 1

	var filtered_candidates: Array[Dictionary] = []
	var total_weight := 0.0
	for candidate: Dictionary in candidates:
		var state := int(candidate.get(&"state", WeatherState.CLEAR))
		var weight := float(candidate.get(&"weight", 0.0))
		if weight <= 0.0:
			continue
		if positive_candidates > 1 and state == current_state:
			continue
		filtered_candidates.append(candidate)
		total_weight += weight

	if total_weight <= 0.0 or filtered_candidates.is_empty():
		return WeatherState.CLEAR

	var roll := _rng.randf() * total_weight
	var cumulative_weight := 0.0
	for candidate: Dictionary in filtered_candidates:
		cumulative_weight += float(candidate.get(&"weight", 0.0))
		if roll <= cumulative_weight:
			return int(candidate.get(&"state", WeatherState.CLEAR))

	return int(filtered_candidates.back().get(&"state", WeatherState.CLEAR))


func _build_state_candidates() -> Array[Dictionary]:
	var after_day_two := GameManager.current_day >= 3
	var clear_weight := 0.82
	var rain_weight := 0.18
	if after_day_two:
		clear_weight = 0.36
		rain_weight = 0.64

	rain_weight += _night_rain_bonus
	clear_weight = maxf(0.12, clear_weight - (_night_rain_bonus * 0.45))

	var acid_mist_weight := 0.0
	var electrical_storm_weight := 0.0
	if _rare_weather_unlocked:
		acid_mist_weight = 0.05 if after_day_two else 0.02
		electrical_storm_weight = 0.04 if after_day_two else 0.01
		if GameManager.has_method("is_night") and GameManager.is_night():
			electrical_storm_weight += 0.03

	return [
		{&"state": WeatherState.CLEAR, &"weight": clear_weight},
		{&"state": WeatherState.RAIN, &"weight": rain_weight},
		{&"state": WeatherState.ACID_MIST, &"weight": acid_mist_weight},
		{&"state": WeatherState.ELECTRICAL_STORM, &"weight": electrical_storm_weight},
	]


func _plan_next_state() -> void:
	_next_state = _pick_next_state()
	_warning_active = false
	_warning_lead_time = -1.0
	if _is_dangerous_weather(_next_state) and _next_state != current_state:
		var minimum_lead := minf(WARNING_LEAD_TIME_RANGE.x, maxf(_state_time_remaining - 1.0, 0.0))
		var maximum_lead := minf(WARNING_LEAD_TIME_RANGE.y, maxf(_state_time_remaining - 1.0, minimum_lead))
		if maximum_lead > 0.0:
			_warning_lead_time = _rng.randf_range(minimum_lead, maximum_lead)
	weather_forecast_changed.emit(_next_state, _state_time_remaining)


func _update_transition_warning() -> void:
	if _warning_active or _warning_lead_time < 0.0 or _state_time_remaining <= 0.0:
		return
	if _state_time_remaining > _warning_lead_time:
		return
	_warning_active = true
	weather_warning_started.emit(_next_state, _state_time_remaining)


func _clear_transition_warning() -> void:
	if _warning_active:
		weather_warning_ended.emit(_next_state)
	_warning_active = false
	_warning_lead_time = -1.0


func _is_dangerous_weather(state: int) -> bool:
	return state == WeatherState.RAIN \
		or state == WeatherState.ACID_MIST \
		or state == WeatherState.ELECTRICAL_STORM


func _apply_environmental_warnings() -> void:
	GameManager.set_environmental_warning(RAIN_WARNING_ID, current_state == WeatherState.RAIN)
	GameManager.set_environmental_warning(ACID_MIST_WARNING_ID, current_state == WeatherState.ACID_MIST)
	GameManager.set_environmental_warning(
		ELECTRICAL_STORM_WARNING_ID,
		current_state == WeatherState.ELECTRICAL_STORM
	)


func _check_sulfur_flats_unlock() -> void:
	if _rare_weather_unlocked:
		return

	var current_scene := get_tree().current_scene
	if current_scene == null or not current_scene.has_method("is_sulfur_flats_at_world_position"):
		return

	var player := GameManager.get_player()
	if player == null:
		return

	if not bool(current_scene.call("is_sulfur_flats_at_world_position", player.global_position)):
		return

	_rare_weather_unlocked = true
	if DiscoveryLog != null and DiscoveryLog.has_method("log_progression_discovery"):
		DiscoveryLog.log_progression_discovery(
			SULFUR_FLATS_UNLOCK_ENTRY_ID,
			SULFUR_FLATS_UNLOCK_TITLE,
			SULFUR_FLATS_UNLOCK_NOTES
		)
	GameManager.mark_dirty()


func _refresh_saved_unlock_state() -> void:
	if _rare_weather_unlocked:
		return
	if DiscoveryLog == null or not DiscoveryLog.has_method("has_discovery"):
		return
	_rare_weather_unlocked = bool(DiscoveryLog.has_discovery(SULFUR_FLATS_UNLOCK_ENTRY_ID))


func _is_weather_active() -> bool:
	return GameManager.game_state == GameManager.GameState.PLAYING and not GameManager.is_paused


func _sync_weather_visuals() -> void:
	_ensure_weather_visuals()
	if _rain_particles == null:
		return

	var should_show_rain := _is_weather_active() and current_state == WeatherState.RAIN
	if should_show_rain:
		if not _rain_particles.emitting:
			_rain_particles.restart()
			_rain_particles.emitting = true
		return

	_rain_particles.emitting = false


func _ensure_weather_visuals() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	if _weather_visual_root != null and not is_instance_valid(_weather_visual_root):
		_weather_visual_root = null
		_rain_particles = null

	if _weather_visual_root != null and _weather_visual_root.get_parent() != current_scene:
		_weather_visual_root.queue_free()
		_weather_visual_root = null
		_rain_particles = null

	if _weather_visual_root != null and _rain_particles != null:
		_layout_weather_visuals(current_scene)
		return

	_weather_visual_root = WEATHER_VISUALS_SCENE.instantiate() as Node2D
	if _weather_visual_root == null:
		return
	current_scene.add_child(_weather_visual_root)
	_rain_particles = _weather_visual_root.get_node_or_null("RainParticles") as GPUParticles2D
	_layout_weather_visuals(current_scene)


func _get_player() -> Node2D:
	return GameManager.get_player()


func _layout_weather_visuals(current_scene: Node) -> void:
	if _weather_visual_root == null or _rain_particles == null:
		return
	var world_rect := _get_scene_world_rect(current_scene)
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return

	var emission_half_width := maxf((world_rect.size.x * 0.5) + RAIN_WORLD_MARGIN, MIN_RAIN_EMISSION_HALF_WIDTH)
	_weather_visual_root.global_position = Vector2(
		world_rect.position.x + world_rect.size.x * 0.5,
		world_rect.position.y - RAIN_WORLD_MARGIN
	)

	var process_material := _rain_particles.process_material as ParticleProcessMaterial
	if process_material != null:
		process_material.emission_box_extents = Vector3(emission_half_width, 16.0, 0.0)

	var required_lifetime := maxf(
		_rain_particles.lifetime,
		(world_rect.size.y + (RAIN_WORLD_MARGIN * 2.0)) / RAIN_PARTICLE_FALL_SPEED
	)
	var emission_rate := float(_rain_particles.amount) / maxf(_rain_particles.lifetime, 0.01)
	_rain_particles.lifetime = required_lifetime
	_rain_particles.amount = maxi(100, int(ceili(emission_rate * required_lifetime)))
	_rain_particles.visibility_rect = Rect2(
		Vector2(-emission_half_width - RAIN_WORLD_MARGIN, -RAIN_WORLD_MARGIN),
		Vector2(
			(emission_half_width + RAIN_WORLD_MARGIN) * 2.0,
			world_rect.size.y + (RAIN_WORLD_MARGIN * 3.0)
		)
	)


func _get_world_tile_coords(world_pos: Vector2) -> Variant:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null

	var ground_layer := current_scene.get_node_or_null("Ground") as TileMapLayer
	if ground_layer == null:
		return null

	return ground_layer.local_to_map(ground_layer.to_local(world_pos))


func _get_scene_world_rect(current_scene: Node) -> Rect2:
	var ground_layer := current_scene.get_node_or_null("Ground") as TileMapLayer
	if ground_layer == null:
		return Rect2()

	var used_rect := ground_layer.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return Rect2()

	var tile_size := Vector2(16.0, 16.0)
	if ground_layer.tile_set != null:
		tile_size = Vector2(ground_layer.tile_set.tile_size)

	var top_left := ground_layer.to_global(ground_layer.map_to_local(used_rect.position) - tile_size * 0.5)
	var world_size := Vector2(float(used_rect.size.x), float(used_rect.size.y)) * tile_size
	return Rect2(top_left, world_size)
