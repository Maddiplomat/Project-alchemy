class_name LabeledProgressBar
extends Control

@export_range(0.0, 1.0, 0.01) var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply_content()
@export var label_format := "%d%%":
	set(value):
		label_format = value
		_apply_content()

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var label: Label = $Label


func _ready() -> void:
	_apply_content()


func set_progress(value: float, text_override := "") -> void:
	progress = clampf(value, 0.0, 1.0)
	if not text_override.is_empty() and is_instance_valid(label):
		label.text = text_override
		progress_bar.value = progress * 100.0
		return
	_apply_content()


func _apply_content() -> void:
	if not is_instance_valid(progress_bar):
		return
	progress_bar.value = progress * 100.0
	label.text = label_format % int(round(progress * 100.0))
