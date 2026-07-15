class_name StyledPanel
extends PanelContainer

@export_range(0, 64, 1) var content_padding := 12:
	set(value):
		content_padding = value
		_apply_padding()

@onready var content: MarginContainer = $Content


func _ready() -> void:
	_apply_padding()


func _apply_padding() -> void:
	if not is_instance_valid(content):
		return
	content.add_theme_constant_override(&"margin_left", content_padding)
	content.add_theme_constant_override(&"margin_top", content_padding)
	content.add_theme_constant_override(&"margin_right", content_padding)
	content.add_theme_constant_override(&"margin_bottom", content_padding)
