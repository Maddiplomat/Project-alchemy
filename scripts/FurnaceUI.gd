extends Control

signal ui_closed

@onready var panel: PanelContainer = $PanelContainer
@onready var close_button: Button = $PanelContainer/VBoxContainer/CloseButton

var _is_open := false


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("interact"):
		close_ui()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_ui()
		get_viewport().set_input_as_handled()


func open_ui() -> void:
	_is_open = true
	visible = true
	close_button.grab_focus()


func close_ui() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	ui_closed.emit()


func _on_close_pressed() -> void:
	close_ui()
