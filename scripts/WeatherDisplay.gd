class_name WeatherDisplay
extends Node

const WeatherSystemScript = preload("res://scripts/WeatherSystem.gd")

var weather_strip: Panel
var status_label: Label
var detail_label: Label
var warning_label: Label
var day_label: Label
var weather_player: Node2D
var _strip_style: StyleBoxFlat


func configure(hud: CanvasLayer) -> void:
	weather_strip = Panel.new()
	weather_strip.name = "WeatherStrip"
	weather_strip.anchor_left = 0.5
	weather_strip.anchor_right = 0.5
	weather_strip.offset_left = -240.0
	weather_strip.offset_top = 16.0
	weather_strip.offset_right = 240.0
	weather_strip.offset_bottom = 132.0
	weather_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(weather_strip)
	_strip_style = StyleBoxFlat.new()
	_strip_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_strip_style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	weather_strip.add_theme_stylebox_override("panel", _strip_style)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12.0
	content.offset_top = 10.0
	content.offset_right = -12.0
	content.offset_bottom = -10.0
	content.add_theme_constant_override("separation", 3)
	weather_strip.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "Weather"
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	day_label = Label.new()
	header.add_child(day_label)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 19)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(status_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(detail_label)
	warning_label = Label.new()
	warning_label.visible = false
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.modulate = Color(1.0, 0.87, 0.48)
	content.add_child(warning_label)
	refresh_day_time()
	refresh()


func refresh_day_time() -> void:
	if day_label == null:
		return
	var total_minutes := int(round(GameManager.time_of_day * 24.0 * 60.0)) % 1440
	day_label.text = "Day %d  %02d:%02d" % [GameManager.current_day, total_minutes / 60, total_minutes % 60]


func refresh() -> void:
	var service := EventBus.get_weather_system()
	if weather_strip == null or service == null or not service.has_method("get_current_state"):
		if weather_strip != null:
			weather_strip.visible = false
		return
	weather_strip.visible = true
	var state := int(service.get_current_state())
	var sheltered := _is_player_sheltered()
	status_label.text = state_name(state)
	detail_label.text = "Danger: %s   Time left: %s\nShelter: %s" % [danger_name(state), format_eta(float(service.get_state_time_remaining())), "Covered" if sheltered else "Exposed"]
	var warning_active := service.has_method("is_transition_warning_active") and bool(service.is_transition_warning_active())
	warning_label.visible = warning_active
	warning_label.text = "Incoming: %s in %s" % [state_name(int(service.get_transition_warning_state())), format_eta(float(service.get_transition_warning_seconds_remaining()))] if warning_active else ""
	_apply_state_style(state, sheltered)


func _apply_state_style(state: int, sheltered: bool) -> void:
	var state_color := Color.WHITE
	match state:
		WeatherSystemScript.WeatherState.RAIN:
			state_color = Color(0.82, 0.92, 1.0, 1.0)
		WeatherSystemScript.WeatherState.ACID_MIST:
			state_color = Color(0.82, 1.0, 0.76, 1.0)
		WeatherSystemScript.WeatherState.ELECTRICAL_STORM:
			state_color = Color(1.0, 0.94, 0.70, 1.0)
	status_label.modulate = state_color
	detail_label.modulate = state_color.lightened(0.08) if sheltered else state_color
	day_label.modulate = Color(1.0, 1.0, 1.0, 0.95)


func state_name(state: int) -> String:
	match state:
		WeatherSystemScript.WeatherState.RAIN: return "Rain"
		WeatherSystemScript.WeatherState.ACID_MIST: return "Acid Mist"
		WeatherSystemScript.WeatherState.ELECTRICAL_STORM: return "Electrical Storm"
		_: return "Clear Skies"


func danger_name(state: int) -> String:
	match state:
		WeatherSystemScript.WeatherState.RAIN: return "Medium"
		WeatherSystemScript.WeatherState.ACID_MIST: return "High"
		WeatherSystemScript.WeatherState.ELECTRICAL_STORM: return "Severe"
		_: return "Low"


func format_eta(seconds: float) -> String:
	var value := maxi(int(round(maxf(seconds, 0.0))), 0)
	if value <= 20: return "under 20s"
	if value < 60: return "about %ds" % value
	if value < 90: return "about 1m"
	if value < 150: return "about 2m"
	return "about %dm" % int(round(float(value) / 60.0))


func _is_player_sheltered() -> bool:
	if weather_player == null or not is_instance_valid(weather_player):
		weather_player = GameManager.get_player()
	if weather_player == null:
		return false
	var service := EventBus.get_weather_system()
	if service != null and service.has_method("get_shelter_at") and service.get_shelter_at(weather_player.global_position):
		return true
	var scene := get_tree().current_scene
	return scene != null and scene.has_method("is_rain_blocked_at_world_position") and scene.call("is_rain_blocked_at_world_position", weather_player.global_position)
