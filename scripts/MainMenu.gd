extends Control

const WORLD_SCENE_PATH := "res://scenes/World.tscn"

@onready var start_button: Button = $CenterContainer/Panel/VBoxContainer/StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)


func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)
