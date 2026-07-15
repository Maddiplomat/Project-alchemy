class_name FurnaceGaugeUI
extends Node

const FurnacePredictionScript = preload("res://scripts/FurnacePrediction.gd")
const FurnaceWarningFXScript = preload("res://scripts/FurnaceWarningFX.gd")
const FURNACE_UI_THEME: FurnaceUITheme = preload("res://assets/themes/furnace_ui_theme.tres")
const CARBON_RATIO_MIN := 0.0
const CARBON_RATIO_MAX := 10.0
const DEFAULT_CONFIG: FurnaceConfig = preload("res://data/config/furnace_config.tres")

var ratio_container: VBoxContainer
var ratio_slider: HSlider
var ratio_value_label: Label
var _ratio_iron_fill: ColorRect
var _ratio_carbon_fill: ColorRect
var _ratio_target_zone: ColorRect
var _ratio_current_marker: ColorRect
var _carbon_slag_zone: ColorRect
var _carbon_optimal_zone: ColorRect
var _danger_zone: ColorRect
var _danger_line: ColorRect
var _temperature_gauge: ProgressBar
var _temp_readout_label: Label
var _danger_label: Label
var _power_status_label: Label
var _power_button: Button
var _warning_fx := FurnaceWarningFXScript.new()
var _config: FurnaceConfig = DEFAULT_CONFIG


func configure(
	owner_ui: CanvasLayer,
	temperature_column: VBoxContainer,
	gauge_frame: Control,
	temperature_gauge: ProgressBar,
	temp_readout_label: Label,
	danger_label: Label,
	danger_zone: ColorRect,
	danger_line: ColorRect,
	close_button: Button,
	furnace_config: FurnaceConfig = DEFAULT_CONFIG
) -> bool:
	_config = furnace_config if furnace_config != null else DEFAULT_CONFIG
	_temperature_gauge = temperature_gauge
	_temp_readout_label = temp_readout_label
	_danger_label = danger_label
	_danger_zone = danger_zone
	_danger_line = danger_line
	ratio_container = temperature_column.get_node_or_null("RatioContainer") as VBoxContainer
	if ratio_container == null:
		push_error("FurnaceUI is missing its pre-baked FurnaceRatioGraph scene.")
		return false
	var graph_frame := ratio_container.get_node_or_null("RatioGraphFrame") as Control
	var graph_background := ratio_container.get_node_or_null("RatioGraphFrame/RatioGraphBackground") as ColorRect
	_ratio_iron_fill = ratio_container.get_node_or_null("RatioGraphFrame/RatioIronFill") as ColorRect
	_ratio_carbon_fill = ratio_container.get_node_or_null("RatioGraphFrame/RatioCarbonFill") as ColorRect
	_ratio_target_zone = ratio_container.get_node_or_null("RatioGraphFrame/RatioTargetZone") as ColorRect
	_ratio_current_marker = ratio_container.get_node_or_null("RatioGraphFrame/RatioCurrentMarker") as ColorRect
	ratio_slider = ratio_container.get_node_or_null("RatioSlider") as HSlider
	ratio_value_label = ratio_container.get_node_or_null("RatioValueLabel") as Label
	if graph_frame == null or graph_background == null or ratio_slider == null or ratio_value_label == null:
		push_error("FurnaceUI's FurnaceRatioGraph scene is incomplete.")
		return false
	ratio_slider.min_value = CARBON_RATIO_MIN
	ratio_slider.max_value = CARBON_RATIO_MAX
	ratio_slider.step = 0.1
	graph_background.color = FURNACE_UI_THEME.ratio_guide_background
	_ratio_iron_fill.color = FURNACE_UI_THEME.ratio_iron_fill
	_ratio_carbon_fill.color = FURNACE_UI_THEME.ratio_carbon_fill
	_ratio_target_zone.color = FURNACE_UI_THEME.ratio_target_zone
	_ratio_current_marker.color = FURNACE_UI_THEME.ratio_current_marker
	_carbon_slag_zone = gauge_frame.get_node_or_null("CarbonSlagZone") as ColorRect
	_carbon_optimal_zone = gauge_frame.get_node_or_null("CarbonOptimalZone") as ColorRect
	_power_status_label = close_button.get_parent().get_node_or_null("PowerStatusLabel") as Label
	_power_button = close_button.get_parent().get_node_or_null("PowerButton") as Button
	if _power_status_label == null or _power_button == null:
		push_error("FurnaceUI is missing its pre-baked power controls.")
		return false
	_power_button.disabled = true
	_warning_fx.ensure_audio_player(owner_ui)
	return true


func update_temperature(current_temp: float, carbonisation_mode: bool) -> void:
	_warning_fx.update_temperature_display(
		current_temp,
		carbonisation_mode,
		{
			"temperature_gauge": _temperature_gauge,
			"temp_readout_label": _temp_readout_label,
			"danger_label": _danger_label,
		},
		{
			"max_temperature": _config.max_temperature,
			"carbonisation_optimal_min": _config.carbonisation_optimal_min,
			"carbonisation_slag_temperature": _config.carbonisation_slag_temperature,
			"carbonisation_flash_temperature": _config.carbonisation_flash_temperature,
			"carbonisation_sfx_temperature": _config.carbonisation_sfx_temperature,
			"carbonisation_good_color": FURNACE_UI_THEME.carbonisation_good,
			"carbonisation_slag_color": FURNACE_UI_THEME.carbonisation_slag,
			"smelting_flash_temperature": _config.smelting_flash_temperature,
			"smelting_sfx_temperature": _config.smelting_sfx_temperature,
			"smelting_explosion_temperature": _config.danger_temperature,
			"warning_flash_speed": _config.warning_flash_speed,
			"gauge_normal_color": FURNACE_UI_THEME.gauge_normal,
			"gauge_danger_color": FURNACE_UI_THEME.gauge_danger,
		}
	)


func set_mode(carbonisation_mode: bool) -> void:
	if ratio_container != null:
		ratio_container.visible = not carbonisation_mode
	if _danger_zone != null:
		_danger_zone.visible = not carbonisation_mode
	if _danger_line != null:
		_danger_line.visible = not carbonisation_mode
	if _carbon_slag_zone != null:
		_carbon_slag_zone.visible = carbonisation_mode
	if _carbon_optimal_zone != null:
		_carbon_optimal_zone.visible = carbonisation_mode


func update_ratio_label(value: float, source_info: Dictionary, formatted_value: String) -> void:
	if ratio_value_label == null:
		return
	ratio_value_label.text = "%s: %s%%" % [str(source_info.get("symbol", "C")), formatted_value]


func update_ratio_guidance(guidance: Dictionary, carbonisation_mode: bool) -> void:
	if ratio_slider == null or ratio_value_label == null:
		return
	var tooltip := str(guidance.get("tooltip", FurnacePredictionScript.RATIO_GUIDE_TOOLTIP_FALLBACK))
	ratio_container.tooltip_text = tooltip
	ratio_slider.tooltip_text = tooltip
	ratio_value_label.tooltip_text = tooltip
	var has_window := bool(guidance.get("has_window", false)) and not carbonisation_mode
	if _ratio_target_zone != null:
		_ratio_target_zone.visible = has_window
		if has_window:
			var min_anchor := inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, float(guidance.get("ratio_min", 0.0)))
			var max_anchor := inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, float(guidance.get("ratio_max", 0.0)))
			_ratio_target_zone.anchor_left = clampf(min_anchor, 0.0, 1.0)
			_ratio_target_zone.anchor_right = clampf(max_anchor, 0.0, 1.0)
			_ratio_target_zone.offset_left = 0.0
			_ratio_target_zone.offset_right = 0.0
	_update_ratio_bar_graph(ratio_slider.value)
	_update_ratio_current_marker(ratio_slider.value)


func update_power_panel(power_state: Dictionary) -> void:
	if _power_status_label == null or _power_button == null:
		return
	var switchboard_enabled := bool(power_state.get(&"switchboard_enabled", true))
	var boost_active := bool(power_state.get(&"boost_active", false))
	var grid_powered := bool(power_state.get(&"grid_powered", false))
	if boost_active:
		_power_status_label.text = "Grid boost active\nHigher heat cap, faster rise, lower fuel burn."
	elif not switchboard_enabled:
		_power_status_label.text = "Boost disabled at the battery station switchboard."
	elif not grid_powered:
		_power_status_label.text = "Boost available through the battery station.\nCharge the defense grid to enable it."
	else:
		_power_status_label.text = "Boost is managed by the battery station switchboard."
	_power_button.text = "Managed at Battery Station"
	_power_button.disabled = true


func _update_ratio_bar_graph(value: float) -> void:
	if _ratio_iron_fill == null or _ratio_carbon_fill == null or ratio_slider == null:
		return
	var normalized := clampf(inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, value), 0.0, 1.0)
	_ratio_iron_fill.anchor_left = 0.0
	_ratio_iron_fill.anchor_right = 1.0 - normalized
	_ratio_iron_fill.offset_left = 0.0
	_ratio_iron_fill.offset_right = 0.0
	_ratio_carbon_fill.anchor_left = 1.0 - normalized
	_ratio_carbon_fill.anchor_right = 1.0
	_ratio_carbon_fill.offset_left = 0.0
	_ratio_carbon_fill.offset_right = 0.0


func _update_ratio_current_marker(value: float) -> void:
	if _ratio_current_marker == null or ratio_slider == null:
		return
	var normalized := clampf(inverse_lerp(ratio_slider.min_value, ratio_slider.max_value, value), 0.0, 1.0)
	_ratio_current_marker.anchor_left = normalized
	_ratio_current_marker.anchor_right = normalized
	_ratio_current_marker.offset_left = -1.0
	_ratio_current_marker.offset_right = 1.0
