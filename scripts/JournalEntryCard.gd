class_name JournalEntryCard
extends PanelContainer

@export var pair_text := "":
	set(value):
		pair_text = value
		_apply_content()
@export var badge_text := "":
	set(value):
		badge_text = value
		_apply_content()
@export var output_text := "":
	set(value):
		output_text = value
		_apply_content()
@export var conditions_text := "":
	set(value):
		conditions_text = value
		_apply_content()

@onready var pair_label: Label = $Margin/Layout/Header/PairLabel
@onready var badge_frame: PanelContainer = $Margin/Layout/Header/BadgeFrame
@onready var badge_label: Label = $Margin/Layout/Header/BadgeFrame/BadgeLabel
@onready var output_label: Label = $Margin/Layout/OutputLabel
@onready var conditions_label: Label = $Margin/Layout/ConditionsLabel


func _ready() -> void:
	_apply_content()


func configure(pair: String, badge: String, output: String, conditions: String, badge_color: Color) -> void:
	pair_text = pair
	badge_text = badge
	output_text = output
	conditions_text = conditions
	_apply_content()
	var style := badge_frame.get_theme_stylebox(&"panel") as StyleBoxFlat
	if style != null:
		style.bg_color = badge_color


func _apply_content() -> void:
	if not is_node_ready():
		return
	pair_label.text = pair_text
	badge_label.text = badge_text
	output_label.text = output_text
	conditions_label.text = conditions_text
