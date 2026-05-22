extends CanvasLayer

signal ui_closed

@onready var root: Control = $Root
@onready var backdrop: ColorRect = $Root/Backdrop
@onready var panel: PanelContainer = $Root/PanelContainer
@onready var title_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var summary_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/SummaryLabel
@onready var recipe_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/RecipePlate/RecipeLabel
@onready var ratio_slider: HSlider = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/RatioSlider
@onready var ratio_value_label: Label = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/RatioValueLabel
@onready var react_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/InstrumentRow/ControlColumn/MarginContainer/VBoxContainer/ReactButton
@onready var close_button: Button = $Root/PanelContainer/MarginContainer/VBoxContainer/FooterRow/CloseButton

var _chem_bench: Node = null


func _ready() -> void:
	visible = false
	root.visible = false
	_apply_theme()
	_update_ratio_label(ratio_slider.value)
	ratio_slider.value_changed.connect(_on_ratio_slider_changed)
	react_button.pressed.connect(_on_react_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		emit_signal("ui_closed")
		get_viewport().set_input_as_handled()


func bind_chem_bench(chem_bench: Node) -> void:
	_chem_bench = chem_bench
	if _chem_bench != null and _chem_bench.has_method("get_active_recipe"):
		var recipe: Dictionary = _chem_bench.get_active_recipe()
		recipe_label.text = "ACTIVE RECIPE: %s" % str(recipe.get(&"display_name", "Rust Bolt"))


func open_ui() -> void:
	visible = true
	root.visible = true


func close_ui() -> void:
	root.visible = false
	visible = false


func _on_ratio_slider_changed(value: float) -> void:
	_update_ratio_label(value)


func _on_react_button_pressed() -> void:
	react_button.text = "Rust Bolt Primed"


func _on_close_button_pressed() -> void:
	emit_signal("ui_closed")


func _update_ratio_label(value: float) -> void:
	ratio_value_label.text = "Reagent Ratio: %.0f / %.0f" % [value, ratio_slider.max_value]


func _apply_theme() -> void:
	backdrop.color = Color(0.01, 0.02, 0.03, 0.54)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.10, 0.97)
	panel_style.border_color = Color(0.42, 0.35, 0.21, 1.0)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", panel_style)

	title_label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.63, 1.0))
	summary_label.add_theme_color_override("font_color", Color(0.70, 0.72, 0.68, 1.0))
	recipe_label.add_theme_color_override("font_color", Color(0.82, 0.66, 0.34, 1.0))
	ratio_value_label.add_theme_color_override("font_color", Color(0.76, 0.81, 0.76, 1.0))

	var react_style := StyleBoxFlat.new()
	react_style.bg_color = Color(0.34, 0.22, 0.12, 1.0)
	react_style.border_color = Color(0.78, 0.55, 0.24, 1.0)
	react_style.border_width_left = 1
	react_style.border_width_right = 1
	react_style.border_width_top = 1
	react_style.border_width_bottom = 1
	react_style.corner_radius_top_left = 6
	react_style.corner_radius_top_right = 6
	react_style.corner_radius_bottom_left = 6
	react_style.corner_radius_bottom_right = 6
	react_button.add_theme_stylebox_override("normal", react_style)
	react_button.add_theme_stylebox_override("hover", react_style)
	react_button.add_theme_stylebox_override("pressed", react_style)
