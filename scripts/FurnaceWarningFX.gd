class_name FurnaceWarningFX
extends RefCounted

const FurnaceWarningAudioBuilder = preload("res://scripts/FurnaceWarningAudioBuilder.gd")

var _warning_audio_player: AudioStreamPlayer
var _warning_audio_stream: AudioStreamWAV
var _warning_mode := ""
var _warning_flash_active := false
var _warning_sfx_fired := false
var _warning_flash_threshold := 0.0
var _warning_sfx_threshold := 0.0
var _warning_result_threshold := 0.0
var _warning_audio_play_count := 0
var _warning_last_audio_temp := -1.0
var _warning_display_text := ""


func ensure_audio_player(owner: Node) -> void:
	if _warning_audio_player != null or owner == null:
		return

	_warning_audio_player = AudioStreamPlayer.new()
	_warning_audio_player.name = "WarningAudioPlayer"
	_warning_audio_player.bus = &"Master"
	_warning_audio_player.volume_db = -9.0
	_warning_audio_stream = FurnaceWarningAudioBuilder.build(_warning_audio_stream)
	_warning_audio_player.stream = _warning_audio_stream
	owner.add_child(_warning_audio_player)


func update_temperature_display(current_temp: float, carbonisation_mode: bool, refs: Dictionary, config: Dictionary) -> void:
	var temperature_gauge: ProgressBar = refs.get("temperature_gauge")
	var temp_readout_label: Label = refs.get("temp_readout_label")
	var danger_label: Label = refs.get("danger_label")
	if temperature_gauge == null or temp_readout_label == null or danger_label == null:
		return

	var clamped_temp := clampf(current_temp, 0.0, float(config.get("max_temperature", 2000.0)))
	temperature_gauge.value = clamped_temp
	temp_readout_label.text = "%d°C" % int(round(clamped_temp))
	_update_warning_state(clamped_temp, carbonisation_mode, config)

	var fill_style: StyleBoxFlat = temperature_gauge.get_theme_stylebox("fill").duplicate()
	if carbonisation_mode:
		var carbon_slag_temperature := float(config.get("carbonisation_slag_temperature", 700.0))
		var carbon_optimal_min := float(config.get("carbonisation_optimal_min", 400.0))
		var is_slag := clamped_temp >= carbon_slag_temperature
		var is_optimal := clamped_temp >= carbon_optimal_min and clamped_temp < carbon_slag_temperature
		var fill_color: Color = config.get("gauge_normal_color", Color(0.95, 0.62, 0.22, 1.0))
		if is_slag:
			fill_color = config.get("carbonisation_slag_color", Color(0.89, 0.29, 0.24, 1.0))
		elif is_optimal:
			fill_color = config.get("carbonisation_good_color", Color(0.34, 0.82, 0.45, 1.0))
		fill_style.bg_color = _get_warning_fill_color(fill_color, Color(1.0, 0.92, 0.72, 1.0), float(config.get("warning_flash_speed", 0.014)))
		temp_readout_label.add_theme_color_override("font_color", fill_color)
		danger_label.text = _warning_display_text if not _warning_display_text.is_empty() else "400-699°C makes Charcoal | 700°C makes Slag"
		danger_label.visible = true
	else:
		var smelting_explosion_temperature := float(config.get("smelting_explosion_temperature", 1600.0))
		var is_danger := clamped_temp >= smelting_explosion_temperature
		var base_color: Color = config.get("gauge_danger_color", Color(0.89, 0.29, 0.24, 1.0)) if is_danger else config.get("gauge_normal_color", Color(0.95, 0.62, 0.22, 1.0))
		fill_style.bg_color = _get_warning_fill_color(base_color, Color(1.0, 0.88, 0.74, 1.0), float(config.get("warning_flash_speed", 0.014)))
		temp_readout_label.add_theme_color_override("font_color", base_color)
		danger_label.text = _warning_display_text if not _warning_display_text.is_empty() else "Overheat warning from 1500°C | Explosion at 1600°C"
		danger_label.visible = _warning_flash_active or is_danger

	temperature_gauge.add_theme_stylebox_override("fill", fill_style)


func get_audio_play_count() -> int:
	return _warning_audio_play_count


func get_last_audio_temp() -> float:
	return _warning_last_audio_temp


func _update_warning_state(current_temp: float, carbonisation_mode: bool, config: Dictionary) -> void:
	var next_mode := "carbonisation" if carbonisation_mode else "smelting"
	var next_flash_threshold := float(config.get("carbonisation_flash_temperature", 650.0)) if carbonisation_mode else float(config.get("smelting_flash_temperature", 1500.0))
	var next_sfx_threshold := float(config.get("carbonisation_sfx_temperature", 680.0)) if carbonisation_mode else float(config.get("smelting_sfx_temperature", 1580.0))
	var next_result_threshold := float(config.get("carbonisation_slag_temperature", 700.0)) if carbonisation_mode else float(config.get("smelting_explosion_temperature", 1600.0))

	if _warning_mode != next_mode:
		_warning_sfx_fired = false
		_warning_last_audio_temp = -1.0

	_warning_mode = next_mode
	_warning_flash_threshold = next_flash_threshold
	_warning_sfx_threshold = next_sfx_threshold
	_warning_result_threshold = next_result_threshold
	_warning_flash_active = current_temp >= _warning_flash_threshold

	if not _warning_flash_active:
		_warning_sfx_fired = false
		_warning_last_audio_temp = -1.0

	if current_temp >= _warning_sfx_threshold and not _warning_sfx_fired:
		_play_warning_audio(current_temp)
		_warning_sfx_fired = true
	elif current_temp < _warning_flash_threshold:
		_warning_sfx_fired = false

	if carbonisation_mode:
		if current_temp >= float(config.get("carbonisation_slag_temperature", 700.0)):
			_warning_display_text = "Overburn warning: 700°C wastes the wood into Slag"
		elif current_temp >= float(config.get("carbonisation_sfx_temperature", 680.0)):
			_warning_display_text = "Critical warning: audio cue at 680°C, Slag at 700°C"
		elif current_temp >= float(config.get("carbonisation_flash_temperature", 650.0)):
			_warning_display_text = "Overburn warning: gauge flashes from 650°C"
		else:
			_warning_display_text = "400-699°C makes Charcoal | 700°C makes Slag"
		return

	if current_temp >= float(config.get("smelting_explosion_temperature", 1600.0)):
		_warning_display_text = "Critical warning: furnace explodes at 1600°C"
	elif current_temp >= float(config.get("smelting_sfx_temperature", 1580.0)):
		_warning_display_text = "Critical warning: audio cue at 1580°C, explosion at 1600°C"
	elif current_temp >= float(config.get("smelting_flash_temperature", 1500.0)):
		_warning_display_text = "Overheat warning: gauge flashes from 1500°C"
	else:
		_warning_display_text = "Overheat warning from 1500°C | Explosion at 1600°C"


func _get_warning_fill_color(base_color: Color, flash_color: Color, flash_speed: float) -> Color:
	if not _warning_flash_active:
		return base_color

	var flash_phase := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * flash_speed)
	return base_color.lerp(flash_color, flash_phase * 0.7)


func _play_warning_audio(current_temp: float) -> void:
	if _warning_audio_player == null:
		return

	_warning_audio_player.stop()
	_warning_audio_player.play()
	_warning_audio_play_count += 1
	_warning_last_audio_temp = current_temp
