extends CanvasLayer

signal buildable_selected(buildable_id: StringName)
signal category_selected(category_id: StringName)
signal rotate_requested
signal confirm_requested
signal cancel_requested

const MOBILE_MARGIN := 14.0
const DESKTOP_PANEL_WIDTH := 540.0
const DESKTOP_PANEL_HEIGHT := 560.0
const MOBILE_PANEL_MAX_HEIGHT := 500.0
const MOBILE_COMPACT_HEIGHT := 156.0
const CARD_CORNER_RADIUS := 18
const BUILDING_CARD_SCENE := preload("res://scenes/UI/BuildingCard.tscn")

@onready var root: Control = $Root
@onready var panel: PanelContainer = $Root/Panel
@onready var title_label: Label = $Root/Panel/Margin/Content/Header/Title
@onready var status_badge: Label = $Root/Panel/Margin/Content/Header/StatusBadge
@onready var compact_button: Button = $Root/Panel/Margin/Content/Header/CompactButton
@onready var hint_label: Label = $Root/Panel/Margin/Content/Hint
@onready var category_scroll: ScrollContainer = $Root/Panel/Margin/Content/CategoryScroll
@onready var categories_row: HBoxContainer = $Root/Panel/Margin/Content/CategoryScroll/Categories
@onready var body_container: BoxContainer = $Root/Panel/Margin/Content/Body
@onready var palette_scroll: ScrollContainer = $Root/Panel/Margin/Content/Body/PaletteScroll
@onready var palette_grid: GridContainer = $Root/Panel/Margin/Content/Body/PaletteScroll/Palette
@onready var selection_panel: PanelContainer = $Root/Panel/Margin/Content/Body/SelectionPanel
@onready var selected_name_label: Label = $Root/Panel/Margin/Content/Body/SelectionPanel/Margin/SelectionContent/SelectedName
@onready var preview_frame: PanelContainer = $Root/Panel/Margin/Content/Body/SelectionPanel/Margin/SelectionContent/PreviewFrame
@onready var preview_texture: TextureRect = $Root/Panel/Margin/Content/Body/SelectionPanel/Margin/SelectionContent/PreviewFrame/Margin/PreviewVBox/PreviewTexture
@onready var placement_label: Label = $Root/Panel/Margin/Content/Body/SelectionPanel/Margin/SelectionContent/PreviewFrame/Margin/PreviewVBox/PlacementLabel
@onready var detail_label: Label = $Root/Panel/Margin/Content/Body/SelectionPanel/Margin/SelectionContent/DetailLabel
@onready var feedback_label: Label = $Root/Panel/Margin/Content/Body/SelectionPanel/Margin/SelectionContent/FeedbackLabel
@onready var rotate_button: Button = $Root/Panel/Margin/Content/ActionRow/RotateButton
@onready var confirm_button: Button = $Root/Panel/Margin/Content/ActionRow/ConfirmButton
@onready var cancel_button: Button = $Root/Panel/Margin/Content/ActionRow/CancelButton

var _category_buttons: Dictionary = {}
var _buildable_cards: Dictionary = {}
var _palette_signature := ""
var _category_signature := ""
var _mobile_palette_compact := false
var _card_default_style := _make_panel_style(Color(0.13, 0.15, 0.18, 0.94), Color(0.26, 0.29, 0.34, 1.0), 2)
var _card_selected_style := _make_panel_style(Color(0.18, 0.30, 0.26, 0.98), Color(0.40, 0.84, 0.63, 1.0), 3)
var _card_locked_style := _make_panel_style(Color(0.18, 0.14, 0.14, 0.92), Color(0.48, 0.32, 0.32, 1.0), 2)
var _card_unaffordable_style := _make_panel_style(Color(0.22, 0.17, 0.11, 0.94), Color(0.86, 0.60, 0.26, 1.0), 2)
var _preview_ready_style := _make_panel_style(Color(0.11, 0.20, 0.18, 0.95), Color(0.40, 0.84, 0.63, 1.0), 3)
var _preview_blocked_style := _make_panel_style(Color(0.23, 0.10, 0.10, 0.95), Color(0.92, 0.36, 0.36, 1.0), 3)
var _preview_warning_style := _make_panel_style(Color(0.26, 0.19, 0.08, 0.95), Color(0.95, 0.75, 0.29, 1.0), 3)


func _ready() -> void:
	layer = 40
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	rotate_button.pressed.connect(func() -> void: rotate_requested.emit())
	confirm_button.pressed.connect(func() -> void: confirm_requested.emit())
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	compact_button.pressed.connect(_toggle_mobile_palette_compact)
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()


func refresh_menu(data: Dictionary) -> void:
	title_label.text = str(data.get(&"title", "Build Mode"))
	hint_label.text = str(data.get(&"hint", ""))

	var status_text := str(data.get(&"status_text", ""))
	status_badge.text = status_text
	status_badge.modulate = _color_for_status(str(data.get(&"status_kind", "neutral")))
	status_badge.visible = not status_text.is_empty()

	var category_entries: Array = data.get(&"categories", [])
	var category_signature := _build_category_signature(category_entries)
	if category_signature != _category_signature:
		_category_signature = category_signature
		_rebuild_categories(category_entries)
	else:
		_refresh_category_states(category_entries)

	var buildable_entries: Array = data.get(&"buildables", [])
	var palette_signature := _build_palette_signature(buildable_entries)
	if palette_signature != _palette_signature:
		_palette_signature = palette_signature
		_rebuild_palette(buildable_entries)
	else:
		_refresh_card_states(buildable_entries)

	_refresh_selected_panel(data.get(&"selected", {}) as Dictionary)
	confirm_button.disabled = not bool(data.get(&"can_confirm", false))
	rotate_button.disabled = not bool(data.get(&"can_rotate", false))


func contains_screen_point(screen_point: Vector2) -> bool:
	return panel.get_global_rect().has_point(screen_point)


func _layout_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var is_mobile_layout := (
		MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()
	) or viewport_size.x < 980.0 or viewport_size.y < 720.0
	panel.reset_size()
	if is_mobile_layout:
		var panel_height := MOBILE_COMPACT_HEIGHT if _mobile_palette_compact else minf(MOBILE_PANEL_MAX_HEIGHT, viewport_size.y * 0.68)
		panel.position = Vector2(MOBILE_MARGIN, viewport_size.y - panel_height - MOBILE_MARGIN)
		panel.size = Vector2(viewport_size.x - MOBILE_MARGIN * 2.0, panel_height)
		compact_button.visible = true
		compact_button.text = "Palette" if _mobile_palette_compact else "Map"
		hint_label.visible = not _mobile_palette_compact
		category_scroll.visible = not _mobile_palette_compact
		body_container.visible = not _mobile_palette_compact
		body_container.vertical = false
		body_container.custom_minimum_size = Vector2.ZERO
		palette_scroll.custom_minimum_size = Vector2.ZERO
		palette_grid.columns = 3
		selection_panel.custom_minimum_size = Vector2(208.0, 0.0)
		preview_frame.custom_minimum_size = Vector2(0.0, 88.0)
		preview_texture.custom_minimum_size = Vector2(56.0, 56.0)
		detail_label.visible = false
	else:
		panel.position = Vector2(viewport_size.x - DESKTOP_PANEL_WIDTH - 18.0, 18.0)
		panel.size = Vector2(DESKTOP_PANEL_WIDTH, minf(DESKTOP_PANEL_HEIGHT, viewport_size.y - 36.0))
		_mobile_palette_compact = false
		compact_button.visible = false
		hint_label.visible = true
		category_scroll.visible = true
		body_container.visible = true
		body_container.vertical = false
		body_container.custom_minimum_size = Vector2(0.0, 320.0)
		palette_scroll.custom_minimum_size = Vector2(0.0, 220.0)
		palette_grid.columns = 2
		selection_panel.custom_minimum_size = Vector2(206.0, 0.0)
		preview_frame.custom_minimum_size = Vector2(0.0, 180.0)
		preview_texture.custom_minimum_size = Vector2(120.0, 120.0)
		detail_label.visible = true


func _toggle_mobile_palette_compact() -> void:
	_mobile_palette_compact = not _mobile_palette_compact
	_layout_panel()


func _rebuild_categories(category_entries: Array) -> void:
	for child in categories_row.get_children():
		child.queue_free()
	_category_buttons.clear()

	for entry_variant in category_entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var category_id := StringName(entry.get(&"id", &""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(112.0, 44.0)
		button.text = str(entry.get(&"label", "Category"))
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_category_pressed.bind(category_id))
		categories_row.add_child(button)
		_category_buttons[category_id] = button

	_refresh_category_states(category_entries)


func _refresh_category_states(category_entries: Array) -> void:
	for entry_variant in category_entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var category_id := StringName(entry.get(&"id", &""))
		var button := _category_buttons.get(category_id) as Button
		if button == null:
			continue
		var is_selected := bool(entry.get(&"selected", false))
		button.button_pressed = is_selected
		button.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_selected else Color(0.84, 0.84, 0.84, 1.0)


func _rebuild_palette(buildable_entries: Array) -> void:
	for child in palette_grid.get_children():
		child.queue_free()
	_buildable_cards.clear()

	for entry_variant in buildable_entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var buildable_id := StringName(entry.get(&"id", &""))
		var card := _create_card(buildable_id)
		palette_grid.add_child(card)
		_buildable_cards[buildable_id] = card

	_refresh_card_states(buildable_entries)


func _refresh_card_states(buildable_entries: Array) -> void:
	for entry_variant in buildable_entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var buildable_id := StringName(entry.get(&"id", &""))
		var card := _buildable_cards.get(buildable_id) as BuildingCard
		if card == null:
			continue

		var texture := entry.get(&"icon") as Texture2D
		card.configure(texture, str(entry.get(&"label", "Unknown")), str(entry.get(&"subtitle", "")))
		card.tooltip_text = str(entry.get(&"tooltip", ""))

		var is_unlocked := bool(entry.get(&"unlocked", false))
		var is_selected := bool(entry.get(&"selected", false))
		var affordable := bool(entry.get(&"affordable", false))
		var style := _card_default_style
		if not is_unlocked:
			style = _card_locked_style
		elif is_selected:
			style = _card_selected_style
		elif not affordable:
			style = _card_unaffordable_style
		card.add_theme_stylebox_override("panel", style)
		card.icon.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_unlocked else Color(0.55, 0.55, 0.55, 1.0)
		card.name_label.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_unlocked else Color(0.82, 0.70, 0.70, 1.0)
		card.meta_label.modulate = Color(0.88, 0.90, 0.94, 1.0) if is_unlocked else Color(0.78, 0.62, 0.62, 1.0)


func _refresh_selected_panel(selected: Dictionary) -> void:
	selected_name_label.text = str(selected.get(&"label", "Choose a buildable"))
	detail_label.text = str(selected.get(&"detail_text", ""))
	feedback_label.text = str(selected.get(&"feedback_text", ""))
	feedback_label.modulate = _color_for_status(str(selected.get(&"feedback_kind", "neutral")))
	placement_label.text = str(selected.get(&"placement_text", ""))
	preview_texture.texture = selected.get(&"icon") as Texture2D
	preview_texture.rotation_degrees = float(selected.get(&"rotation_degrees", 0.0))

	match str(selected.get(&"preview_kind", "neutral")):
		"ready":
			preview_frame.add_theme_stylebox_override("panel", _preview_ready_style)
		"warning":
			preview_frame.add_theme_stylebox_override("panel", _preview_warning_style)
		"blocked":
			preview_frame.add_theme_stylebox_override("panel", _preview_blocked_style)
		_:
			preview_frame.add_theme_stylebox_override("panel", _card_default_style)


func _create_card(buildable_id: StringName) -> BuildingCard:
	var card := BUILDING_CARD_SCENE.instantiate() as BuildingCard
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.focus_mode = Control.FOCUS_NONE
	card.gui_input.connect(_on_card_gui_input.bind(buildable_id))
	return card


func _on_category_pressed(category_id: StringName) -> void:
	category_selected.emit(category_id)


func _on_card_gui_input(event: InputEvent, buildable_id: StringName) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			buildable_selected.emit(buildable_id)
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			buildable_selected.emit(buildable_id)


func _build_category_signature(category_entries: Array) -> String:
	var parts: Array[String] = []
	for entry_variant in category_entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		parts.append("%s:%s" % [String(entry.get(&"id", &"")), str(entry.get(&"selected", false))])
	return "|".join(parts)


func _build_palette_signature(buildable_entries: Array) -> String:
	var parts: Array[String] = []
	for entry_variant in buildable_entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		parts.append(
			"%s:%s:%s:%s:%s" % [
				String(entry.get(&"id", &"")),
				str(entry.get(&"selected", false)),
				str(entry.get(&"unlocked", false)),
				str(entry.get(&"affordable", false)),
				str(entry.get(&"subtitle", "")),
			]
		)
	return "|".join(parts)


func _make_panel_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := UIFactory.panel_style()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = CARD_CORNER_RADIUS
	style.corner_radius_top_right = CARD_CORNER_RADIUS
	style.corner_radius_bottom_right = CARD_CORNER_RADIUS
	style.corner_radius_bottom_left = CARD_CORNER_RADIUS
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _color_for_status(status_kind: String) -> Color:
	match status_kind:
		"ready":
			return Color(0.50, 0.92, 0.67, 1.0)
		"warning":
			return Color(0.98, 0.82, 0.38, 1.0)
		"blocked":
			return Color(0.96, 0.49, 0.49, 1.0)
		_:
			return Color(0.92, 0.94, 0.98, 1.0)
