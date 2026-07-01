extends Node

signal cold_level_changed(current: float, maximum: float)
signal player_warmed_changed(is_warmed: bool)

const COLD_BUILDUP_RATE: float = 2.0
const COLD_DECAY_RATE: float = 5.0
const COLD_MAX: float = 100.0
const COLD_DAMAGE_TICK_RATE: float = 2.0

var cold_level: float = 0.0
var is_player_warmed: bool = false

var _cold_damage_timer: float = 0.0


func _ready() -> void:
	EventBus.register_service(EventBus.SERVICE_COLD_SYSTEM, self)
	if GameManager != null and GameManager.has_signal("new_game_started"):
		GameManager.new_game_started.connect(reset_state)


func _exit_tree() -> void:
	EventBus.unregister_service(EventBus.SERVICE_COLD_SYSTEM, self)


func _process(delta: float) -> void:
	if GameManager == null:
		return
	if GameManager.game_state != GameManager.GameState.PLAYING or GameManager.is_paused:
		return
	_update_cold_level(delta)


func get_cold_level() -> float:
	return cold_level


func is_warmed() -> bool:
	return is_player_warmed


func set_player_warmed(value: bool) -> void:
	if is_player_warmed == value:
		return
	is_player_warmed = value
	player_warmed_changed.emit(is_player_warmed)


func reset_state() -> void:
	_cold_damage_timer = 0.0
	set_player_warmed(false)
	_set_cold_level(0.0)


func _update_cold_level(delta: float) -> void:
	var player_position: Variant = GameManager.get_player_world_position()
	var cold_buildup_multiplier := 1.0
	var warmth_decay_multiplier := 1.0
	var effectively_warmed := is_player_warmed
	if GameManager.is_night() and has_node("/root/BaseThreatDirector") and player_position != null:
		cold_buildup_multiplier = float(BaseThreatDirector.get_cold_buildup_multiplier(player_position))
		warmth_decay_multiplier = float(BaseThreatDirector.get_warmth_decay_multiplier(player_position))
		effectively_warmed = bool(BaseThreatDirector.should_count_as_warmed(player_position))

	if not GameManager.is_night():
		_set_cold_level(maxf(0.0, cold_level - COLD_DECAY_RATE * delta))
	elif effectively_warmed:
		_set_cold_level(maxf(0.0, cold_level - COLD_DECAY_RATE * warmth_decay_multiplier * delta))
	else:
		_set_cold_level(minf(COLD_MAX, cold_level + COLD_BUILDUP_RATE * cold_buildup_multiplier * delta))

	if cold_level >= COLD_MAX and not effectively_warmed:
		_cold_damage_timer += delta
		if _cold_damage_timer >= COLD_DAMAGE_TICK_RATE:
			GameManager.damage_player(2)
			_cold_damage_timer = 0.0
	else:
		_cold_damage_timer = 0.0


func _set_cold_level(value: float) -> void:
	var next_level := clampf(value, 0.0, COLD_MAX)
	if is_equal_approx(cold_level, next_level):
		return
	cold_level = next_level
	cold_level_changed.emit(cold_level, COLD_MAX)
