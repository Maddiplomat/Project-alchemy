extends CanvasLayer

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const DEATH_OVERLAY_FADE_SECONDS := 1.0
const DISCOVERY_JOURNAL_SCENE := preload("res://scenes/UI/DiscoveryJournal.tscn")

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
@onready var held_item_icon: TextureRect = $HeldItemContainer/HBoxContainer/ActiveItemIcon
@onready var held_item_label: Label = $HeldItemContainer/HBoxContainer/ActiveItemLabel
@onready var carry_vignette: ColorRect = $CarryVignette
@onready var death_overlay: Panel = $DeathOverlay
@onready var death_cause_label: Label = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/CauseLabel
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

func _ready() -> void:
	GameManager.player_health_changed.connect(_update_health)
	GameManager.player_died.connect(_show_death_overlay)
	InventoryManager.inventory_changed.connect(_refresh_held_item)
	InventoryManager.held_item_changed.connect(_on_held_item_changed)
	InventoryManager.weight_changed.connect(_on_weight_changed)
	retry_button.pressed.connect(_on_retry_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

	_update_health(GameManager.player_health, GameManager.max_player_health)
	_refresh_held_item()
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)
	_hide_death_overlay()
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
	held_item_label.text = str(element_data.get("display_name", item_id))

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
	retry_button.disabled = true
	quit_button.disabled = true
	_death_overlay_tween = create_tween()
	_death_overlay_tween.tween_property(death_overlay, "modulate:a", 1.0, DEATH_OVERLAY_FADE_SECONDS)
	_death_overlay_tween.finished.connect(_on_death_overlay_fade_finished)


func _hide_death_overlay() -> void:
	death_overlay.visible = false
	death_overlay.modulate.a = 0.0
	death_cause_label.text = "Cause of death: Unknown"
	retry_button.disabled = false
	quit_button.disabled = false


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

func _get_item_color(item_id: String) -> Color:
	match item_id:
		"wood":
			return Color.BURLYWOOD
		"stone":
			return Color.GRAY
		"iron":
			return Color.SILVER
		"charcoal":
			return Color(0.17, 0.18, 0.20, 1.0)
		_:
			return Color.WHITE

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
