extends CanvasLayer

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const DEATH_OVERLAY_FADE_SECONDS := 1.0

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

var _placeholder_textures := {}
var _death_overlay_tween: Tween = null

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


func _format_cause_of_death(cause_of_death: StringName) -> String:
	match cause_of_death:
		&"physical":
			return "Physical damage"
		&"burn":
			return "Burn damage"
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
