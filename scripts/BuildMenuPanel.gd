extends CanvasLayer

const PANEL_SIZE := Vector2(456.0, 420.0)

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/Content/Title
@onready var hint_label: Label = $Panel/Margin/Content/Hint
@onready var buildables_text: RichTextLabel = $Panel/Margin/Content/Scroll/BuildablesText


func _ready() -> void:
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.custom_minimum_size = PANEL_SIZE
	panel.offset_right = 16.0 + PANEL_SIZE.x
	panel.offset_bottom = 16.0 + PANEL_SIZE.y


func refresh_menu(title: String, hint: String, buildables: String) -> void:
	title_label.text = title
	hint_label.text = hint
	buildables_text.text = buildables


func contains_screen_point(screen_point: Vector2) -> bool:
	return panel.get_global_rect().has_point(screen_point)
