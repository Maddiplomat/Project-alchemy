extends Control

const WORLD_SCENE_PATH := "res://scenes/World.tscn"

@onready var continue_button: Button = $CenterContainer/Panel/VBoxContainer/ContinueButton
@onready var load_button: Button = $CenterContainer/Panel/VBoxContainer/LoadButton
@onready var start_button: Button = $CenterContainer/Panel/VBoxContainer/StartButton
@onready var save_status_label: Label = $CenterContainer/Panel/VBoxContainer/SaveStatusLabel


func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.MAIN_MENU)
	continue_button.pressed.connect(_on_continue_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)
	start_button.pressed.connect(_on_start_button_pressed)
	if GameManager.has_signal("active_save_slot_changed") and not GameManager.active_save_slot_changed.is_connected(_refresh_save_ui):
		GameManager.active_save_slot_changed.connect(_refresh_save_ui)
	_refresh_save_ui()


func _on_start_button_pressed() -> void:
	GameManager.start_new_game()
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)


func _on_continue_button_pressed() -> void:
	var continue_slot := GameManager.get_continue_slot() if GameManager.has_method("get_continue_slot") else GameManager.active_save_slot
	if continue_slot <= 0:
		_refresh_save_ui()
		return
	GameManager.request_load_game(continue_slot)
	if GameManager.game_state != GameManager.GameState.LOADING:
		_refresh_save_ui()


func _on_load_button_pressed() -> void:
	GameManager.request_load_game(GameManager.active_save_slot)
	if GameManager.game_state != GameManager.GameState.LOADING:
		_refresh_save_ui()


func _refresh_save_ui() -> void:
	var continue_slot := GameManager.get_continue_slot() if GameManager.has_method("get_continue_slot") else -1
	var has_save := GameManager.has_method("has_save_data") and bool(GameManager.has_save_data(GameManager.active_save_slot))
	continue_button.disabled = continue_slot <= 0
	load_button.disabled = not has_save
	load_button.text = "Load Slot %d" % GameManager.active_save_slot
	if not has_save:
		save_status_label.text = "No local save found in slot %d." % GameManager.active_save_slot
		return
	var metadata := GameManager.get_save_metadata(GameManager.active_save_slot) if GameManager.has_method("get_save_metadata") else {}
	save_status_label.text = _format_save_status(metadata)


func _format_save_status(metadata: Dictionary) -> String:
	if metadata.is_empty():
		return "Local save available."
	var saved_at_unix := int(metadata.get("saved_at_unix", 0))
	var day_value := int(metadata.get("current_day", 0))
	var scene_path := str(metadata.get("current_scene_path", ""))
	var scene_name := scene_path.get_file().get_basename() if not scene_path.is_empty() else "world"
	if saved_at_unix <= 0:
		return "Slot %d: Day %d in %s." % [GameManager.active_save_slot, maxi(day_value, 1), scene_name]
	var saved_at := Time.get_datetime_dict_from_unix_time(saved_at_unix)
	return "Slot %d: Day %d in %s. Saved %02d-%02d-%04d %02d:%02d." % [
		GameManager.active_save_slot,
		maxi(day_value, 1),
		scene_name,
		int(saved_at.get("day", 0)),
		int(saved_at.get("month", 0)),
		int(saved_at.get("year", 0)),
		int(saved_at.get("hour", 0)),
		int(saved_at.get("minute", 0)),
	]
