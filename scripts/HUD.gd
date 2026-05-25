extends CanvasLayer

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const DEATH_OVERLAY_FADE_SECONDS := 1.0
const DISCOVERY_JOURNAL_SCENE := preload("res://scenes/UI/DiscoveryJournal.tscn")
const CARRIER_WARNING_SFX_DURATION := 0.11

@onready var carrier_risk_strip: Panel = $CarrierRiskStrip
@onready var carrier_risk_warning_label: Label = $CarrierRiskStrip/VBoxContainer/WarningLabel
@onready var carrier_risk_hint_label: Label = $CarrierRiskStrip/VBoxContainer/HintLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
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

func _ready() -> void:
	GameManager.player_health_changed.connect(_update_health)
	GameManager.player_died.connect(_show_death_overlay)
	InventoryManager.inventory_changed.connect(_refresh_held_item)
	InventoryManager.held_item_changed.connect(_on_held_item_changed)
	InventoryManager.weight_changed.connect(_on_weight_changed)
	retry_button.pressed.connect(_on_retry_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	if has_node("/root/CarrierRiskSystem"):
		CarrierRiskSystem.carrier_risk_warning.connect(_on_carrier_risk_warning)
		CarrierRiskSystem.carrier_risk_cleared.connect(_on_carrier_risk_cleared)
		CarrierRiskSystem.carrier_risk_ignition.connect(_on_carrier_risk_ignition)

	_update_health(GameManager.player_health, GameManager.max_player_health)
	_refresh_held_item()
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)
	_hide_death_overlay()
	_hide_carrier_risk_warning()
	_setup_carrier_warning_audio()
	_setup_discovery_journal()

	if debug_seed_journal_entries > 0:
		DiscoveryLog.seed_debug_entries(debug_seed_journal_entries, true)

	if debug_open_journal_on_ready:
		call_deferred("_open_debug_journal")


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

func _update_health(current_health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_label.text = "%d / %d HP" % [current_health, max_health]

func _refresh_held_item() -> void:
	var held_item := InventoryManager.get_held_item()
	if held_item.is_empty():
		held_item_icon.texture = null
		held_item_icon.modulate = Color(1.0, 1.0, 1.0, 0.25)
		held_item_label.text = "Hands Empty"
		return

	var item_id := str(held_item.get("id", ""))
	var element_data := ElementDatabase.get_element(StringName(item_id))
	held_item_icon.texture = _get_placeholder_texture(item_id)
	held_item_icon.modulate = _get_item_color(item_id)
	held_item_label.text = (
		str(element_data.get("display_name", item_id))
		if not element_data.is_empty() else
		str(held_item.get("display_name", item_id))
	)

func _on_held_item_changed(_item_id: String) -> void:
	_refresh_held_item()

func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	var capacity_ratio := 0.0
	if carry_capacity > 0.0:
		capacity_ratio = total_weight / carry_capacity

	var overlay_alpha := 0.0
	if capacity_ratio >= CARRY_VIGNETTE_START_RATIO:
		var alpha_ratio := inverse_lerp(CARRY_VIGNETTE_START_RATIO, CARRY_VIGNETTE_END_RATIO, minf(capacity_ratio, CARRY_VIGNETTE_END_RATIO))
		overlay_alpha = alpha_ratio * CARRY_VIGNETTE_MAX_ALPHA

	carry_vignette.color.a = overlay_alpha


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
	carrier_risk_strip.visible = false
	carrier_risk_warning_label.text = "SULFUR UNSTABLE - 3s"
	carrier_risk_hint_label.text = "Drop Sulfur from inventory to cancel"


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
