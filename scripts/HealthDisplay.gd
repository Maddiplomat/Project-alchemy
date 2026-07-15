class_name HealthDisplay
extends Node

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const FADE_SECONDS := 1.0

var health_bar: ProgressBar
var health_label: Label
var overlay: Panel
var cause_label: Label
var hits_label: Label
var retry_button: Button
var quit_button: Button
var _fade_tween: Tween


func configure(bar: ProgressBar, label: Label, death_overlay: Panel, death_cause: Label, last_hits: Label, retry: Button, quit: Button) -> void:
	health_bar = bar
	health_label = label
	overlay = death_overlay
	cause_label = death_cause
	hits_label = last_hits
	retry_button = retry
	quit_button = quit
	retry_button.pressed.connect(retry_game)
	quit_button.pressed.connect(quit_to_menu)


func update_health(current_health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_label.text = "%d / %d HP" % [current_health, max_health]


func show_death(cause: StringName) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	overlay.visible = true
	overlay.modulate.a = 0.0
	cause_label.text = "Cause of death: %s" % _format_cause(cause)
	hits_label.text = _build_last_hits_text()
	retry_button.disabled = true
	quit_button.disabled = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(overlay, "modulate:a", 1.0, FADE_SECONDS)
	_fade_tween.finished.connect(func() -> void:
		retry_button.disabled = false
		quit_button.disabled = false
	)


func hide_death() -> void:
	overlay.visible = false
	overlay.modulate.a = 0.0
	cause_label.text = "Cause of death: Unknown"
	hits_label.text = "Last hits:\nNo recent damage recorded."
	retry_button.disabled = false
	quit_button.disabled = false


func retry_game() -> void:
	GameManager.start_new_game()
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)


func quit_to_menu() -> void:
	GameManager.set_game_state(GameManager.GameState.MAIN_MENU)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _format_cause(cause: StringName) -> String:
	match cause:
		&"physical": return "Physical damage"
		&"burn": return "Burn damage"
		&"explosion": return "Explosion damage"
		&"Furnace overheated": return "Furnace overheated"
		&"toxic": return "Toxic exposure"
		&"radiation": return "Radiation exposure"
		&"unknown", &"": return "Unknown"
		_: return String(cause).replace("_", " ").capitalize()


func _build_last_hits_text() -> String:
	var health_system := GameManager.player_health_system
	if health_system == null or not health_system.has_method("get_recent_damage_entries"):
		return "Last hits:\nNo recent damage recorded."
	var entries: Array = health_system.get_recent_damage_entries(3)
	if entries.is_empty():
		return "Last hits:\nNo recent damage recorded."
	var lines: Array[String] = ["Last hits:"]
	for index in range(entries.size() - 1, -1, -1):
		var entry := entries[index] as Dictionary
		var source := str(entry.get(&"source_label", "")).strip_edges()
		if source.is_empty():
			source = _format_cause(StringName(entry.get(&"damage_type", &"physical")))
		var damage_type := String(entry.get(&"damage_type", &"physical")).replace("_", " ").strip_edges()
		lines.append("%s - %d %s damage" % [source, int(entry.get(&"amount", 0)), damage_type if not damage_type.is_empty() else "physical"])
	return "\n".join(lines)
