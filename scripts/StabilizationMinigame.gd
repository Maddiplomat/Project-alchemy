extends CanvasLayer

signal stabilization_succeeded
signal stabilization_failed(reason: StringName)

const HEAT_LIMIT := 100.0
const HEAT_RISE_PER_SECOND := 15.0
const HEAT_VENT_DROP := 25.0
const HEAT_VENT_COOLDOWN_SECONDS := 2.0
const PRESSURE_MIN := 0.0
const PRESSURE_MAX := 100.0
const PRESSURE_SAFE_MIN := 45.0
const PRESSURE_SAFE_MAX := 55.0
const PRESSURE_DRIFT_PER_SECOND := 18.0
const PRESSURE_MOVE_PAUSE_SECONDS := 2.0
const REACTION_DURATION_SECONDS := 10.0

@onready var root: Control = $Root
@onready var overlay: ColorRect = $Root/Overlay
@onready var title_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var status_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/HeaderRow/StatusLabel
@onready var heat_gauge: ProgressBar = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/HeatPanel/MarginContainer/VBoxContainer/HeatGauge
@onready var heat_value_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/HeatPanel/MarginContainer/VBoxContainer/HeatValueLabel
@onready var vent_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/HeatPanel/MarginContainer/VBoxContainer/VentButton
@onready var vent_cooldown_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/HeatPanel/MarginContainer/VBoxContainer/VentCooldownLabel
@onready var pressure_slider: HSlider = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/PressurePanel/MarginContainer/VBoxContainer/PressureSlider
@onready var pressure_value_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/PressurePanel/MarginContainer/VBoxContainer/PressureValueLabel
@onready var pressure_target_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/PressurePanel/MarginContainer/VBoxContainer/PressureTargetLabel
@onready var timer_gauge: ProgressBar = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/TimerPanel/MarginContainer/VBoxContainer/TimerGauge
@onready var timer_value_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/GaugeRow/TimerPanel/MarginContainer/VBoxContainer/TimerValueLabel

var _active := false
var _heat := 0.0
var _vent_cooldown_remaining := 0.0
var _reaction_time_remaining := REACTION_DURATION_SECONDS
var _pressure_target := 50.0
var _pressure_pause_remaining := 0.0
var _pressure_value := 50.0


func _ready() -> void:
	visible = false
	root.visible = false
	overlay.color = Color(0.0, 0.0, 0.0, 0.85)
	vent_button.pressed.connect(_on_vent_button_pressed)
	pressure_slider.value_changed.connect(_on_pressure_slider_value_changed)
	_reset_state()
	set_process(true)


func start(recipe_name: String = "Stabilization") -> void:
	_reset_state()
	title_label.text = "%s Stabilization" % recipe_name
	status_label.text = "Hold heat below the limit and finish with pressure centered."
	visible = true
	root.visible = true
	_active = true


func stop() -> void:
	_active = false
	root.visible = false
	visible = false


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return

	_heat = minf(HEAT_LIMIT, _heat + HEAT_RISE_PER_SECOND * delta)
	_reaction_time_remaining = maxf(0.0, _reaction_time_remaining - delta)
	_vent_cooldown_remaining = maxf(0.0, _vent_cooldown_remaining - delta)
	_pressure_pause_remaining = maxf(0.0, _pressure_pause_remaining - delta)
	if _pressure_pause_remaining <= 0.0:
		_pressure_value = move_toward(_pressure_value, _pressure_target, PRESSURE_DRIFT_PER_SECOND * delta)
		if is_equal_approx(_pressure_value, _pressure_target):
			_pressure_pause_remaining = PRESSURE_MOVE_PAUSE_SECONDS
			_pick_new_pressure_target()
	pressure_slider.value = _pressure_value

	_refresh_ui()

	if _heat >= HEAT_LIMIT:
		_fail(&"heat_runaway")
		return
	if _pressure_value <= PRESSURE_MIN or _pressure_value >= PRESSURE_MAX:
		_fail(&"pressure_spike")
		return
	if _reaction_time_remaining <= 0.0:
		if _pressure_value >= PRESSURE_SAFE_MIN and _pressure_value <= PRESSURE_SAFE_MAX:
			_succeed()
		else:
			_fail(&"timer_expiry")


func _on_vent_button_pressed() -> void:
	if not _active or _vent_cooldown_remaining > 0.0:
		return
	_heat = maxf(0.0, _heat - HEAT_VENT_DROP)
	_vent_cooldown_remaining = HEAT_VENT_COOLDOWN_SECONDS
	_refresh_ui()

func _on_pressure_slider_value_changed(value: float) -> void:
	_pressure_value = value


func _pick_new_pressure_target() -> void:
	_pressure_target = randf_range(8.0, 92.0)


func _reset_state() -> void:
	_heat = 20.0
	_vent_cooldown_remaining = 0.0
	_reaction_time_remaining = REACTION_DURATION_SECONDS
	_pressure_pause_remaining = 0.0
	pressure_slider.min_value = PRESSURE_MIN
	pressure_slider.max_value = PRESSURE_MAX
	pressure_slider.step = 0.1
	_pressure_value = 50.0
	pressure_slider.value = _pressure_value
	_pick_new_pressure_target()
	_refresh_ui()


func _refresh_ui() -> void:
	heat_gauge.max_value = HEAT_LIMIT
	heat_gauge.value = _heat
	heat_value_label.text = "Heat %.0f / %.0f" % [_heat, HEAT_LIMIT]
	vent_button.disabled = _vent_cooldown_remaining > 0.0
	vent_cooldown_label.text = (
		"Vent cooldown %.1fs" % _vent_cooldown_remaining
		if _vent_cooldown_remaining > 0.0 else
		"Vent ready"
	)

	pressure_value_label.text = "Pressure %.1f | Safe 45-55" % _pressure_value
	pressure_target_label.text = "Spike target %.0f" % _pressure_target
	var pressure_in_safe_zone := _pressure_value >= PRESSURE_SAFE_MIN and _pressure_value <= PRESSURE_SAFE_MAX
	pressure_value_label.modulate = Color(0.64, 0.90, 0.68, 1.0) if pressure_in_safe_zone else Color(0.95, 0.74, 0.38, 1.0)

	timer_gauge.max_value = REACTION_DURATION_SECONDS
	timer_gauge.value = _reaction_time_remaining
	timer_value_label.text = "Reaction %.1fs" % _reaction_time_remaining


func _succeed() -> void:
	if not _active:
		return
	_active = false
	stop()
	stabilization_succeeded.emit()


func _fail(reason: StringName) -> void:
	if not _active:
		return
	_active = false
	stop()
	stabilization_failed.emit(reason)
