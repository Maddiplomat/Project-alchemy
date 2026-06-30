extends CanvasLayer

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const DEATH_OVERLAY_FADE_SECONDS := 1.0
const DISCOVERY_JOURNAL_SCENE := preload("res://scenes/UI/Journal.tscn")
const CARRIER_WARNING_SFX_DURATION := 0.11
const SCANNER_TOAST_SECONDS := 1.6
const NIGHT_DEFENSE_TOAST_SECONDS := 2.2

@onready var carrier_risk_strip: Panel = $CarrierRiskStrip
@onready var carrier_risk_warning_label: Label = $CarrierRiskStrip/VBoxContainer/WarningLabel
@onready var carrier_risk_hint_label: Label = $CarrierRiskStrip/VBoxContainer/HintLabel
@onready var scanner_upgrade_label: Label = $ScannerUpgradeLabel
@onready var objectives_panel: Panel = $ObjectivesPanel
@onready var objective_title_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var objective_1_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/Objective1Label
@onready var objective_2_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/Objective2Label
@onready var objective_3_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/Objective3Label
@onready var day_time_label: Label = $DayTimeLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
@onready var weight_label: Label = $WeightLabel
@onready var held_item_icon: TextureRect = $HeldItemContainer/HBoxContainer/ActiveItemIcon
@onready var held_item_label: Label = $HeldItemContainer/HBoxContainer/ActiveItemLabel
@onready var carry_vignette: ColorRect = $CarryVignette
@onready var death_overlay: Panel = $DeathOverlay
@onready var death_cause_label: Label = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/CauseLabel
@onready var death_last_hits_label: Label = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/LastHitsLabel
@onready var retry_button: Button = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/RetryButton
@onready var quit_button: Button = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/QuitButton

const CARRY_VIGNETTE_MAX_ALPHA := 0.35
const CARRY_VIGNETTE_START_RATIO := 0.9
const CARRY_VIGNETTE_END_RATIO := 1.0
const CARRIER_VIGNETTE_PULSE_SPEED := 5.5
const CARRIER_VIGNETTE_URGENT_SPEED := 9.0
const OBJECTIVES_PANEL_DEFAULT_TOP := 44.0
const OBJECTIVES_PANEL_DEFAULT_BOTTOM := 166.0

@export var debug_seed_journal_entries := 0
@export var debug_open_journal_on_ready := false
@export var debug_report_journal_layout := false

var _placeholder_textures := {}
var _death_overlay_tween: Tween = null
var _journal_panel: Panel = null
var _journal_open := false
var _paused_player: Node = null
var _carrier_warning_audio_player: AudioStreamPlayer = null
var _active_carrier_risk_element: StringName = &""
var _active_carrier_risk_seconds := -1
var _weight_vignette_alpha := 0.0
var _carrier_vignette_phase := 0.0
var _scanner_upgrade_tween: Tween = null
var _night_defense_strip: Panel = null
var _night_defense_label: Label = null
var _night_defense_tween: Tween = null
var _objectives_panel_visible := true
var _toast_queue: Array[String] = []
var _is_toast_playing := false
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _weather_strip: Panel = null
var _weather_strip_style: StyleBoxFlat = null
var _weather_status_label: Label = null
var _weather_detail_label: Label = null
var _weather_warning_label: Label = null
var _weather_day_label: Label = null
var _weather_player: Node2D = null

func _ready() -> void:
	GameManager.player_health_changed.connect(_update_health)
	GameManager.player_died.connect(_show_death_overlay)
	GameManager.scanner_tier_changed.connect(_on_scanner_tier_changed)
	GameManager.day_changed.connect(_on_day_changed)
	GameManager.time_of_day_changed.connect(_on_time_of_day_changed)
	InventoryManager.inventory_changed.connect(_refresh_held_item.unbind(1))
	InventoryManager.active_slot_changed.connect(_on_held_item_changed.unbind(1))
	InventoryManager.weight_changed.connect(_on_weight_changed)
	if ResearchObjectives != null:
		ResearchObjectives.objective_completed.connect(_on_objectives_changed)
		ResearchObjectives.objective_activated.connect(_on_objectives_changed)
	retry_button.pressed.connect(_on_retry_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	if has_node("/root/CarrierRiskSystem"):
		CarrierRiskSystem.carrier_risk_warning.connect(_on_carrier_risk_warning)
		CarrierRiskSystem.carrier_risk_cleared.connect(_on_carrier_risk_cleared)
		CarrierRiskSystem.carrier_risk_ignition.connect(_on_carrier_risk_ignition)

	_update_health(GameManager.player_health, GameManager.max_player_health)
	_refresh_held_item()
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)
	_refresh_day_time()
	_refresh_objectives()
	_hide_death_overlay()
	_hide_carrier_risk_warning()
	_hide_scanner_upgrade_toast()
	_setup_carrier_warning_audio()
	_setup_discovery_journal()
	_setup_night_defense_warning()
	_setup_weather_strip()
	if has_node("/root/BaseDefenseSystem"):
		BaseDefenseSystem.night_threat_detected.connect(_on_night_threat_detected)
	if has_node("/root/BaseThreatDirector"):
		BaseThreatDirector.threat_lesson_triggered.connect(_on_base_threat_lesson_triggered)
	if WeatherSystem != null:
		if WeatherSystem.has_signal("weather_warning_started"):
			WeatherSystem.weather_warning_started.connect(_on_weather_warning_started)
		if WeatherSystem.has_signal("weather_warning_ended"):
			WeatherSystem.weather_warning_ended.connect(_on_weather_warning_ended)

	if debug_seed_journal_entries > 0:
		DiscoveryLog.seed_debug_entries(debug_seed_journal_entries, true)

	if debug_open_journal_on_ready:
		call_deferred("_open_debug_journal")

	_setup_toast_notification()
	GameManager.environmental_warning_changed.connect(_on_environmental_warning_changed)


func _process(delta: float) -> void:
	if _active_carrier_risk_seconds > 0:
		_carrier_vignette_phase += delta * (
			CARRIER_VIGNETTE_URGENT_SPEED if _active_carrier_risk_seconds <= 1 else CARRIER_VIGNETTE_PULSE_SPEED
		)
		_update_carry_vignette()
	_update_weather_strip()


func _unhandled_input(event: InputEvent) -> void:
	if death_overlay.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _journal_open:
		_close_journal()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_journal"):
		if _journal_open:
			_close_journal()
		else:
			_open_journal()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		_toggle_objectives_panel()
		get_viewport().set_input_as_handled()


func _toggle_objectives_panel() -> void:
	_objectives_panel_visible = not _objectives_panel_visible
	if objectives_panel != null:
		objectives_panel.visible = _objectives_panel_visible

func _update_health(current_health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_label.text = "%d / %d HP" % [current_health, max_health]

func _refresh_held_item() -> void:
	var held_item := InventoryManager.get_slot_data(InventoryManager.active_slot_index)
	if held_item.item_id == &"" or held_item.quantity <= 0:
		held_item_icon.texture = null
		held_item_icon.modulate = Color(1.0, 1.0, 1.0, 0.25)
		held_item_label.text = "Hands Empty"
		return

	var item_id := String(held_item.item_id)
	var element_data := ElementDatabase.get_element(held_item.item_id)
	held_item_icon.texture = _get_placeholder_texture(item_id)
	held_item_icon.modulate = _get_item_color(item_id)
	held_item_label.text = (
		str(element_data.get("display_name", item_id))
		if not element_data.is_empty() else item_id
	)

func _on_held_item_changed() -> void:
	_refresh_held_item()

func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	weight_label.text = "%.1f / %.1f kg" % [total_weight, carry_capacity]
	var capacity_ratio := 0.0
	if carry_capacity > 0.0:
		capacity_ratio = total_weight / carry_capacity

	_weight_vignette_alpha = 0.0
	if capacity_ratio >= CARRY_VIGNETTE_START_RATIO:
		var alpha_ratio := inverse_lerp(CARRY_VIGNETTE_START_RATIO, CARRY_VIGNETTE_END_RATIO, minf(capacity_ratio, CARRY_VIGNETTE_END_RATIO))
		_weight_vignette_alpha = alpha_ratio * CARRY_VIGNETTE_MAX_ALPHA
	_update_carry_vignette()


func _on_day_changed(_day: int) -> void:
	_refresh_day_time()


func _on_time_of_day_changed(_time_of_day: float) -> void:
	_refresh_day_time()


func _refresh_day_time() -> void:
	var day_time_text := _get_day_time_text()
	day_time_label.text = day_time_text
	if _weather_day_label != null:
		_weather_day_label.text = day_time_text


func _on_objectives_changed(_objective_id: StringName) -> void:
	_refresh_objectives()


func _refresh_objectives() -> void:
	var lines: Array[String] = []
	if ResearchObjectives != null and ResearchObjectives.has_method("get_all_objectives"):
		var objective_list: Array[Dictionary] = ResearchObjectives.get_all_objectives()
		for objective: Dictionary in objective_list:
			if bool(objective.get(&"completed", false)):
				continue
			var title := str(objective.get(&"title", "Untitled Objective"))
			var hint := str(objective.get(&"hint", ""))
			var prefix := "[Active] " if bool(objective.get(&"active", false)) else "[Queued] "
			var line := "%s%s" % [prefix, title]
			if not hint.is_empty():
				line = "%s - %s" % [line, hint]
			lines.append(line)
			if lines.size() >= 3:
				break

	objective_title_label.text = "Research Objectives"
	objective_1_label.text = lines[0] if lines.size() > 0 else "No active objectives"
	objective_2_label.text = lines[1] if lines.size() > 1 else ""
	objective_3_label.text = lines[2] if lines.size() > 2 else ""
	objectives_panel.visible = _objectives_panel_visible


func _show_death_overlay(cause_of_death: StringName) -> void:
	if _death_overlay_tween != null:
		_death_overlay_tween.kill()

	death_overlay.visible = true
	death_overlay.modulate.a = 0.0
	death_cause_label.text = "Cause of death: %s" % _format_cause_of_death(cause_of_death)
	death_last_hits_label.text = _build_last_hits_text()
	retry_button.disabled = true
	quit_button.disabled = true
	_death_overlay_tween = create_tween()
	_death_overlay_tween.tween_property(death_overlay, "modulate:a", 1.0, DEATH_OVERLAY_FADE_SECONDS)
	_death_overlay_tween.finished.connect(_on_death_overlay_fade_finished)


func _hide_death_overlay() -> void:
	death_overlay.visible = false
	death_overlay.modulate.a = 0.0
	death_cause_label.text = "Cause of death: Unknown"
	death_last_hits_label.text = "Last hits:\nNo recent damage recorded."
	retry_button.disabled = false
	quit_button.disabled = false


func _on_carrier_risk_warning(element_id: StringName, seconds_remaining: int) -> void:
	_active_carrier_risk_element = element_id
	_active_carrier_risk_seconds = seconds_remaining
	carrier_risk_strip.visible = true
	carrier_risk_warning_label.text = "%s UNSTABLE - %ds" % [_get_risk_item_name(element_id).to_upper(), seconds_remaining]
	carrier_risk_hint_label.text = "Drop %s from inventory to cancel" % _get_risk_item_name(element_id)
	_update_carry_vignette()
	if seconds_remaining == 1:
		_play_carrier_warning_sfx()


func _on_carrier_risk_cleared(element_id: StringName) -> void:
	if element_id != _active_carrier_risk_element:
		return
	_hide_carrier_risk_warning()


func _on_carrier_risk_ignition(element_id: StringName) -> void:
	if element_id == _active_carrier_risk_element:
		_hide_carrier_risk_warning()


func _hide_carrier_risk_warning() -> void:
	_active_carrier_risk_element = &""
	_active_carrier_risk_seconds = -1
	_carrier_vignette_phase = 0.0
	carrier_risk_strip.visible = false
	carrier_risk_warning_label.text = "SULFUR UNSTABLE - 3s"
	carrier_risk_hint_label.text = "Drop Sulfur from inventory to cancel"
	_update_carry_vignette()


func _on_scanner_tier_changed(previous_tier: int, new_tier: int) -> void:
	if previous_tier != GameManager.ScannerTier.BASIC or new_tier != GameManager.ScannerTier.ADVANCED:
		return
	_show_scanner_upgrade_toast()


func _show_scanner_upgrade_toast() -> void:
	if _scanner_upgrade_tween != null:
		_scanner_upgrade_tween.kill()

	scanner_upgrade_label.text = "Scanner upgraded"
	scanner_upgrade_label.visible = true
	scanner_upgrade_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_scanner_upgrade_tween = create_tween()
	_scanner_upgrade_tween.tween_property(scanner_upgrade_label, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	_scanner_upgrade_tween.tween_interval(SCANNER_TOAST_SECONDS)
	_scanner_upgrade_tween.tween_property(scanner_upgrade_label, "modulate:a", 0.0, 0.28).set_ease(Tween.EASE_IN)
	_scanner_upgrade_tween.tween_callback(_hide_scanner_upgrade_toast)


func _hide_scanner_upgrade_toast() -> void:
	scanner_upgrade_label.visible = false
	scanner_upgrade_label.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _setup_night_defense_warning() -> void:
	_night_defense_strip = Panel.new()
	_night_defense_strip.name = "NightDefenseStrip"
	_night_defense_strip.visible = false
	_night_defense_strip.offset_left = 24.0
	_night_defense_strip.offset_top = 120.0
	_night_defense_strip.offset_right = 384.0
	_night_defense_strip.offset_bottom = 164.0
	add_child(_night_defense_strip)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.10, 0.07, 0.92)
	style.border_color = Color(0.88, 0.62, 0.24, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_night_defense_strip.add_theme_stylebox_override("panel", style)

	_night_defense_label = Label.new()
	_night_defense_label.offset_left = 12.0
	_night_defense_label.offset_top = 10.0
	_night_defense_label.offset_right = 344.0
	_night_defense_label.offset_bottom = 34.0
	_night_defense_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_night_defense_label.text = "Movement detected in the powered perimeter."
	_night_defense_strip.add_child(_night_defense_label)


func _setup_weather_strip() -> void:
	_weather_strip = Panel.new()
	_weather_strip.name = "WeatherStrip"
	_weather_strip.anchor_left = 0.5
	_weather_strip.anchor_right = 0.5
	_weather_strip.offset_left = -240.0
	_weather_strip.offset_top = 16.0
	_weather_strip.offset_right = 240.0
	_weather_strip.offset_bottom = 132.0
	_weather_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_weather_strip)

	_weather_strip_style = StyleBoxFlat.new()
	_weather_strip_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_weather_strip_style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	_weather_strip_style.border_width_left = 0
	_weather_strip_style.border_width_top = 0
	_weather_strip_style.border_width_right = 0
	_weather_strip_style.border_width_bottom = 0
	_weather_strip_style.corner_radius_top_left = 0
	_weather_strip_style.corner_radius_top_right = 0
	_weather_strip_style.corner_radius_bottom_left = 0
	_weather_strip_style.corner_radius_bottom_right = 0
	_weather_strip.add_theme_stylebox_override("panel", _weather_strip_style)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12.0
	content.offset_top = 10.0
	content.offset_right = -12.0
	content.offset_bottom = -10.0
	content.add_theme_constant_override("separation", 3)
	_weather_strip.add_child(content)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(header_row)

	var title_label := Label.new()
	title_label.text = "Weather"
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_row.add_child(title_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)

	_weather_day_label = Label.new()
	_weather_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weather_day_label.text = _get_day_time_text()
	header_row.add_child(_weather_day_label)

	_weather_status_label = Label.new()
	_weather_status_label.text = "Clear Skies"
	_weather_status_label.add_theme_font_size_override("font_size", 19)
	_weather_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_weather_status_label)

	_weather_detail_label = Label.new()
	_weather_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weather_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weather_detail_label.text = "Danger: Low   Time left: about 3m\nShelter: Exposed"
	content.add_child(_weather_detail_label)

	_weather_warning_label = Label.new()
	_weather_warning_label.visible = false
	_weather_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weather_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weather_warning_label.modulate = Color(1.0, 0.87, 0.48, 1.0)
	content.add_child(_weather_warning_label)

	if day_time_label != null:
		day_time_label.visible = false

	if objectives_panel != null:
		objectives_panel.offset_top = OBJECTIVES_PANEL_DEFAULT_TOP
		objectives_panel.offset_bottom = OBJECTIVES_PANEL_DEFAULT_BOTTOM

	_update_weather_strip()


func _on_night_threat_detected(_world_position: Vector2, stack_count: int) -> void:
	if _night_defense_strip == null or _night_defense_label == null:
		return
	if _night_defense_tween != null:
		_night_defense_tween.kill()
	_night_defense_label.text = "Movement detected in the powered perimeter. Light stack: %d" % stack_count
	_night_defense_strip.visible = true
	_night_defense_strip.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_night_defense_tween = create_tween()
	_night_defense_tween.tween_property(_night_defense_strip, "modulate:a", 1.0, 0.16)
	_night_defense_tween.tween_interval(NIGHT_DEFENSE_TOAST_SECONDS)
	_night_defense_tween.tween_property(_night_defense_strip, "modulate:a", 0.0, 0.24)
	_night_defense_tween.tween_callback(func() -> void:
		if _night_defense_strip != null:
			_night_defense_strip.visible = false
	)


func _on_weather_warning_started(target_state: int, seconds_remaining: float) -> void:
	_queue_toast(
		"%s incoming in %s. Shelter or store sensitive materials now."
			% [_get_weather_state_name(target_state), _format_weather_eta(seconds_remaining)]
	)
	_update_weather_strip()


func _on_weather_warning_ended(_target_state: int) -> void:
	_update_weather_strip()


func _on_death_overlay_fade_finished() -> void:
	retry_button.disabled = false
	quit_button.disabled = false


func _on_retry_button_pressed() -> void:
	GameManager.start_new_game()
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)


func _on_quit_button_pressed() -> void:
	GameManager.set_game_state(GameManager.GameState.MAIN_MENU)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _setup_discovery_journal() -> void:
	_journal_panel = DISCOVERY_JOURNAL_SCENE.instantiate()
	add_child(_journal_panel)
	if _journal_panel.has_signal("close_requested"):
		_journal_panel.close_requested.connect(_close_journal)
	if _journal_panel.has_method("hide_panel"):
		_journal_panel.hide_panel()


func _setup_carrier_warning_audio() -> void:
	_carrier_warning_audio_player = AudioStreamPlayer.new()
	add_child(_carrier_warning_audio_player)
	_carrier_warning_audio_player.stream = _build_carrier_warning_stream()


func _play_carrier_warning_sfx() -> void:
	if _carrier_warning_audio_player == null or _carrier_warning_audio_player.stream == null:
		return
	_carrier_warning_audio_player.stop()
	_carrier_warning_audio_player.play()


func _open_journal() -> void:
	if _journal_panel == null or _journal_open:
		return

	_pause_player_input()
	_journal_open = true
	_journal_panel.show_panel()


func _close_journal() -> void:
	if _journal_panel == null or not _journal_open:
		return

	_journal_open = false
	_journal_panel.hide_panel()
	_resume_player_input()


func _pause_player_input() -> void:
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player == null or not player.has_method("pause_input"):
		return

	_paused_player = player
	player.pause_input()


func _resume_player_input() -> void:
	if _paused_player == null or not is_instance_valid(_paused_player):
		_paused_player = null
		return
	if _paused_player.has_method("resume_input"):
		_paused_player.resume_input()
	_paused_player = null


func _open_debug_journal() -> void:
	_open_journal()
	if debug_report_journal_layout and _journal_panel != null and _journal_panel.has_method("debug_report_layout"):
		await get_tree().process_frame
		await get_tree().process_frame
		_journal_panel.debug_report_layout()


func _format_cause_of_death(cause_of_death: StringName) -> String:
	match cause_of_death:
		&"physical":
			return "Physical damage"
		&"burn":
			return "Burn damage"
		&"explosion":
			return "Explosion damage"
		&"Furnace overheated":
			return "Furnace overheated"
		&"toxic":
			return "Toxic exposure"
		&"radiation":
			return "Radiation exposure"
		&"unknown", &"":
			return "Unknown"
		_:
			return String(cause_of_death).replace("_", " ").capitalize()


func _build_last_hits_text() -> String:
	var health_system := GameManager.player_health_system
	if health_system == null or not health_system.has_method("get_recent_damage_entries"):
		return "Last hits:\nNo recent damage recorded."

	var recent_entries: Array = health_system.get_recent_damage_entries(3)
	if recent_entries.is_empty():
		return "Last hits:\nNo recent damage recorded."

	var lines: Array[String] = ["Last hits:"]
	for index in range(recent_entries.size() - 1, -1, -1):
		lines.append(_format_damage_log_entry(recent_entries[index]))
	return "\n".join(lines)


func _format_damage_log_entry(entry: Dictionary) -> String:
	var source_label := str(entry.get(&"source_label", "")).strip_edges()
	if source_label.is_empty():
		source_label = _format_cause_of_death(StringName(entry.get(&"damage_type", &"physical")))

	var amount := int(entry.get(&"amount", 0))
	var damage_type := _format_damage_type(StringName(entry.get(&"damage_type", &"physical")))
	return "%s - %d %s" % [source_label, amount, damage_type]


func _format_damage_type(damage_type: StringName) -> String:
	var normalized := String(damage_type).replace("_", " ").strip_edges()
	if normalized.is_empty():
		normalized = "physical"
	return "%s damage" % normalized

func _get_item_color(item_id: String) -> Color:
	match item_id:
		"wood":
			return Color.BURLYWOOD
		"stone":
			return Color.GRAY
		"iron":
			return Color.SILVER
		"steel":
			return Color(0.70, 0.76, 0.82, 1.0)
		"charcoal":
			return Color(0.17, 0.18, 0.20, 1.0)
		"lithium":
			return Color(0.76, 0.88, 1.0, 1.0)
		"rust_bolt":
			return Color(0.84, 0.38, 0.12, 1.0)
		"sulfuric_bolt":
			return Color(0.76, 0.90, 0.22, 1.0)
		"steel_sword":
			return Color(0.82, 0.85, 0.90, 1.0)
		_:
			return Color.WHITE


func _get_risk_item_name(item_id: StringName) -> String:
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", item_id))
	return String(item_id).replace("_", " ").capitalize()


func _update_weather_strip() -> void:
	if _weather_strip == null or _weather_status_label == null or _weather_detail_label == null:
		return
	if WeatherSystem == null or not WeatherSystem.has_method("get_current_state"):
		_weather_strip.visible = false
		return

	_weather_strip.visible = true
	var current_state := int(WeatherSystem.get_current_state())
	var sheltered := _is_player_sheltered()
	_weather_status_label.text = _get_weather_state_name(current_state)
	_weather_detail_label.text = "Danger: %s   Time left: %s\nShelter: %s" % [
		_get_weather_danger_label(current_state),
		_format_weather_eta(float(WeatherSystem.get_state_time_remaining())),
		"Covered" if sheltered else "Exposed",
	]

	var warning_active := WeatherSystem.has_method("is_transition_warning_active") \
		and bool(WeatherSystem.is_transition_warning_active())
	if warning_active:
		var target_state := int(WeatherSystem.get_transition_warning_state())
		var warning_eta := float(WeatherSystem.get_transition_warning_seconds_remaining())
		_weather_warning_label.visible = true
		_weather_warning_label.text = "Incoming: %s in %s" % [
			_get_weather_state_name(target_state),
			_format_weather_eta(warning_eta),
		]
	else:
		_weather_warning_label.visible = false
		_weather_warning_label.text = ""

	_apply_weather_strip_style(current_state, sheltered)


func _apply_weather_strip_style(current_state: int, sheltered: bool) -> void:
	if _weather_strip_style == null or _weather_status_label == null or _weather_detail_label == null:
		return
	match current_state:
		WeatherSystem.WeatherState.RAIN:
			_weather_status_label.modulate = Color(0.82, 0.92, 1.0, 1.0)
			_weather_detail_label.modulate = Color(0.82, 0.92, 1.0, 1.0)
		WeatherSystem.WeatherState.ACID_MIST:
			_weather_status_label.modulate = Color(0.82, 1.0, 0.76, 1.0)
			_weather_detail_label.modulate = Color(0.82, 1.0, 0.76, 1.0)
		WeatherSystem.WeatherState.ELECTRICAL_STORM:
			_weather_status_label.modulate = Color(1.0, 0.94, 0.70, 1.0)
			_weather_detail_label.modulate = Color(1.0, 0.94, 0.70, 1.0)
		_:
			_weather_status_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_weather_detail_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if _weather_day_label != null:
		_weather_day_label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	if sheltered:
		_weather_detail_label.modulate = _weather_detail_label.modulate.lightened(0.08)


func _get_weather_state_name(state: int) -> String:
	match state:
		WeatherSystem.WeatherState.RAIN:
			return "Rain"
		WeatherSystem.WeatherState.ACID_MIST:
			return "Acid Mist"
		WeatherSystem.WeatherState.ELECTRICAL_STORM:
			return "Electrical Storm"
		_:
			return "Clear Skies"


func _get_weather_danger_label(state: int) -> String:
	match state:
		WeatherSystem.WeatherState.RAIN:
			return "Medium"
		WeatherSystem.WeatherState.ACID_MIST:
			return "High"
		WeatherSystem.WeatherState.ELECTRICAL_STORM:
			return "Severe"
		_:
			return "Low"


func _format_weather_eta(seconds: float) -> String:
	var clamped_seconds := maxi(int(round(maxf(seconds, 0.0))), 0)
	if clamped_seconds <= 20:
		return "under 20s"
	if clamped_seconds < 60:
		return "about %ds" % clamped_seconds
	if clamped_seconds < 90:
		return "about 1m"
	if clamped_seconds < 150:
		return "about 2m"
	return "about %dm" % int(round(float(clamped_seconds) / 60.0))


func _get_day_time_text() -> String:
	var total_minutes: int = int(round(GameManager.time_of_day * 24.0 * 60.0)) % (24 * 60)
	var hour: int = int(floor(float(total_minutes) / 60.0))
	var minute: int = total_minutes % 60
	return "Day %d  %02d:%02d" % [GameManager.current_day, hour, minute]


func _get_weather_player() -> Node2D:
	if _weather_player != null and is_instance_valid(_weather_player):
		return _weather_player
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	_weather_player = current_scene.find_child("Player", true, false) as Node2D
	return _weather_player


func _is_player_sheltered() -> bool:
	var player := _get_weather_player()
	if player == null:
		return false
	if WeatherSystem != null and WeatherSystem.has_method("get_shelter_at"):
		if bool(WeatherSystem.get_shelter_at(player.global_position)):
			return true
	var current_scene := get_tree().current_scene
	return current_scene != null \
		and current_scene.has_method("is_rain_blocked_at_world_position") \
		and bool(current_scene.call("is_rain_blocked_at_world_position", player.global_position))


func _update_carry_vignette() -> void:
	var risk_alpha := 0.0
	if _active_carrier_risk_seconds > 0:
		var pulse := 0.5 + (0.5 * sin(_carrier_vignette_phase))
		var minimum_alpha := 0.12 if _active_carrier_risk_seconds > 1 else 0.22
		var maximum_alpha := 0.24 if _active_carrier_risk_seconds > 1 else 0.34
		risk_alpha = lerpf(minimum_alpha, maximum_alpha, pulse)

	carry_vignette.color = Color(
		carry_vignette.color.r,
		carry_vignette.color.g,
		carry_vignette.color.b,
		clampf(_weight_vignette_alpha + risk_alpha, 0.0, 0.45)
	)


func _build_carrier_warning_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count := int(sample_rate * CARRIER_WARNING_SFX_DURATION)
	var data := PackedByteArray()
	data.resize(frame_count * 2)

	for frame in range(frame_count):
		var t := float(frame) / float(sample_rate)
		var envelope := 1.0 - (float(frame) / float(frame_count))
		var sample := (
			sin(TAU * 1480.0 * t) * 0.45
			+ sin(TAU * 2120.0 * t) * 0.18
		) * envelope * 0.8
		var sample_value := int(clampi(int(sample * 32767.0), -32768, 32767))
		var packed_value := sample_value & 0xffff
		data[frame * 2] = packed_value & 0xff
		data[frame * 2 + 1] = (packed_value >> 8) & 0xff

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _get_placeholder_texture(item_id: String) -> Texture2D:
	if _placeholder_textures.has(item_id):
		return _placeholder_textures[item_id]

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.WHITE)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 48
	texture.height = 48
	_placeholder_textures[item_id] = texture
	return texture

func _setup_toast_notification() -> void:
	_toast_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_color = Color(0.8, 0.7, 0.2, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_toast_panel.add_theme_stylebox_override("panel", style)
	_toast_panel.modulate.a = 0.0
	
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 20)
	
	_toast_panel.add_child(_toast_label)
	add_child(_toast_panel)
	
	_toast_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_panel.offset_top = 100
	_toast_panel.offset_bottom = 140
	_toast_panel.offset_left = 300
	_toast_panel.offset_right = -300
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.z_index = 100
	
	if ElementDatabase != null:
		ElementDatabase.element_discovered.connect(_on_element_discovered_toast)

func _on_element_discovered_toast(element_id: StringName) -> void:
	var elem = ElementDatabase.get_element(element_id)
	if elem.is_empty():
		return
	var display_name = str(elem.get("display_name", element_id))
	_queue_toast("%s discovered — new entries added to journal" % display_name)
	
	for recipe_id in RecipeDatabase.recipes.keys():
		var recipe = RecipeDatabase.get_recipe(recipe_id)
		if recipe.get("requires_discovery") == element_id:
			_queue_toast("New recipe available: %s" % recipe.get("name", recipe_id))


func _on_environmental_warning_changed(warning_id: StringName, active: bool) -> void:
	if not active:
		return
	match warning_id:
		&"rain":
			_queue_toast("Rain started — carried lithium charge drains unless sheltered or stored dry.")
		&"electrical_storm":
			_queue_toast("Electrical storm — carried lithium slowly recharges while the storm holds.")
		&"acid_mist":
			_queue_toast("Acid Mist — exposed sulfur nodes are degrading in the open.")
		_:
			pass


func _on_base_threat_lesson_triggered(_lesson_id: StringName, message: String) -> void:
	_queue_toast(message)

func _queue_toast(message: String) -> void:
	_toast_queue.append(message)
	_play_next_toast()

func _play_next_toast() -> void:
	if _is_toast_playing or _toast_queue.is_empty():
		return
		
	_is_toast_playing = true
	var message = _toast_queue.pop_front()
	_toast_label.text = message
	
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
		
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.finished.connect(func():
		_is_toast_playing = false
		_play_next_toast()
	)
