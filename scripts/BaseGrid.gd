extends Node

signal power_activated
signal power_deactivated
signal charge_level_changed(current_charge: float, max_charge: float)

const MAX_CHARGE: float = 30.0
const CHARGE_PER_CELL: float = 20.0
const DRAIN_TICK_SECONDS := 0.25

var charge_level: float = 0.0
var _is_powered: bool = false
var _drain_timer: Timer = null
var _last_drain_tick_msec := 0


func _ready() -> void:
	EventBus.register_service(EventBus.SERVICE_BASE_GRID, self)
	_drain_timer = Timer.new()
	_drain_timer.wait_time = DRAIN_TICK_SECONDS
	_drain_timer.timeout.connect(_on_drain_tick)
	add_child(_drain_timer)
	_sync_drain_timer()


func _exit_tree() -> void:
	EventBus.unregister_service(EventBus.SERVICE_BASE_GRID, self)


func _on_drain_tick() -> void:
	var now_msec := Time.get_ticks_msec()
	var elapsed_seconds := DRAIN_TICK_SECONDS if _last_drain_tick_msec <= 0 else maxf(
		float(now_msec - _last_drain_tick_msec) / 1000.0,
		0.0
	)
	_last_drain_tick_msec = now_msec
	if charge_level <= 0.0:
		_sync_drain_timer()
		return
	if EventBus.get_base_defense_system() == null or not EventBus.get_base_defense_system().has_method("get_total_drain_per_second"):
		return

	var current_drain := float(EventBus.get_base_defense_system().get_total_drain_per_second())
	if current_drain <= 0.0:
		return

	charge_level = maxf(0.0, charge_level - current_drain * elapsed_seconds)
	_sync_power_state()


func add_charge(amount: float) -> void:
	if amount <= 0.0:
		return
	charge_level = minf(MAX_CHARGE, charge_level + amount)
	_sync_power_state()


func add_charge_cell() -> void:
	add_charge(CHARGE_PER_CELL)


func consume_charge(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if charge_level < amount:
		return false
	charge_level = maxf(0.0, charge_level - amount)
	_sync_power_state()
	return true


func is_powered() -> bool:
	return _is_powered


func get_charge_percentage() -> float:
	return charge_level / MAX_CHARGE if MAX_CHARGE > 0.0 else 0.0


func get_charge_state() -> float:
	return charge_level


func restore_charge_level(value: float) -> void:
	charge_level = clampf(value, 0.0, MAX_CHARGE)
	_sync_power_state()


func _sync_power_state() -> void:
	var was_powered := _is_powered
	_is_powered = charge_level > 0.0
	charge_level_changed.emit(charge_level, MAX_CHARGE)
	if not was_powered and _is_powered:
		power_activated.emit()
	elif was_powered and not _is_powered:
		power_deactivated.emit()
	_sync_drain_timer()


func _sync_drain_timer() -> void:
	if _drain_timer == null:
		return
	if charge_level > 0.0:
		if _drain_timer.is_stopped():
			_last_drain_tick_msec = Time.get_ticks_msec()
			_drain_timer.start()
	else:
		_drain_timer.stop()
		_last_drain_tick_msec = 0
