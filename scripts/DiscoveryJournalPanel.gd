extends Panel

const DebugLog = preload("res://scripts/DebugLog.gd")

signal close_requested

const FILTER_ALL := "all"
const FILTER_SUCCESSES := "successes"
const FILTER_FAILURES := "failures"
const FILTER_UNKNOWNS := "unknowns"

const PARCHMENT_BG := Color(0.90, 0.84, 0.70, 0.98)
const PARCHMENT_EDGE := Color(0.45, 0.31, 0.18, 1.0)
const PARCHMENT_SHADOW := Color(0.27, 0.17, 0.09, 0.36)
const INK_COLOR := Color(0.21, 0.14, 0.09, 1.0)
const MUTED_INK_COLOR := Color(0.34, 0.24, 0.16, 0.88)
const SUCCESS_COLOR := Color(0.35, 0.54, 0.25, 1.0)
const FAILURE_COLOR := Color(0.63, 0.28, 0.19, 1.0)
const UNKNOWN_COLOR := Color(0.48, 0.42, 0.29, 1.0)
const DANGER_COLOR := Color(0.54, 0.13, 0.10, 1.0)

@onready var title_label: Label = $MarginContainer/Content/TitleRow/TitleLabel
@onready var subtitle_label: Label = $MarginContainer/Content/TitleRow/SubtitleLabel
@onready var all_button: Button = $MarginContainer/Content/FilterRow/AllButton
@onready var successes_button: Button = $MarginContainer/Content/FilterRow/SuccessesButton
@onready var failures_button: Button = $MarginContainer/Content/FilterRow/FailuresButton
@onready var unknowns_button: Button = $MarginContainer/Content/FilterRow/UnknownsButton
@onready var scroll_container: ScrollContainer = $MarginContainer/Content/EntriesFrame/EntriesScroll
@onready var entries_list: VBoxContainer = $MarginContainer/Content/EntriesFrame/EntriesScroll/EntriesList
@onready var footer_label: Label = $MarginContainer/Content/FooterLabel

var _filter_buttons: Dictionary[String, Button] = {}
var _active_filter := FILTER_ALL


func _ready() -> void:
	_filter_buttons = {
		FILTER_ALL: all_button,
		FILTER_SUCCESSES: successes_button,
		FILTER_FAILURES: failures_button,
		FILTER_UNKNOWNS: unknowns_button,
	}
	_apply_theme()
	_wire_events()
	_refresh_entries()


func show_panel() -> void:
	visible = true
	_refresh_entries()


func hide_panel() -> void:
	visible = false
	release_focus()


func debug_report_layout() -> void:
	var content_height := entries_list.size.y
	var viewport_height := scroll_container.size.y
	var requires_scroll := content_height > viewport_height
	DebugLog.info(
		"[DiscoveryJournal] entries=%d viewport_height=%.1f content_height=%.1f requires_scroll=%s overflow_ok=%s"
		% [
			entries_list.get_child_count(),
			viewport_height,
			content_height,
			str(requires_scroll),
			str(requires_scroll and viewport_height > 0.0),
		]
	)


func _wire_events() -> void:
	all_button.pressed.connect(func() -> void: _set_filter(FILTER_ALL))
	successes_button.pressed.connect(func() -> void: _set_filter(FILTER_SUCCESSES))
	failures_button.pressed.connect(func() -> void: _set_filter(FILTER_FAILURES))
	unknowns_button.pressed.connect(func() -> void: _set_filter(FILTER_UNKNOWNS))
	DiscoveryLog.entry_added.connect(_on_log_changed)


func _set_filter(filter_id: String) -> void:
	if _active_filter == filter_id:
		return
	_active_filter = filter_id
	_refresh_entries()


func _on_log_changed(_entry: Dictionary) -> void:
	_refresh_entries()


func _refresh_entries() -> void:
	_clear_entries()
	_update_filter_button_states()

	var entries := DiscoveryLog.get_entries()
	var filtered_count := 0
	for entry: Dictionary in entries:
		if not _matches_filter(entry):
			continue
		filtered_count += 1
		entries_list.add_child(_build_entry_card(entry))

	title_label.text = "Discovery Journal"
	subtitle_label.text = (
		"Use Close or Journal to dismiss."
		if MobileInputRouter != null and MobileInputRouter.prefers_touch_controls() else
		"Press J to close."
	)
	footer_label.text = (
		"%d entries shown" % filtered_count
		if filtered_count > 0 else
		"No matching discoveries yet."
	)


func _clear_entries() -> void:
	for child in entries_list.get_children():
		child.queue_free()


func _matches_filter(entry: Dictionary) -> bool:
	match _active_filter:
		FILTER_SUCCESSES:
			return _is_success(entry)
		FILTER_FAILURES:
			return _is_failure(entry)
		FILTER_UNKNOWNS:
			return _is_unknown(entry)
		_:
			return true


func _is_success(entry: Dictionary) -> bool:
	var tier := str(entry.get("tier", "unknown"))
	return tier == "optimal" or tier == "medium" or tier == "low" or tier == "success"


func _is_failure(entry: Dictionary) -> bool:
	var tier := str(entry.get("tier", "unknown"))
	return tier == "waste" or tier == "danger"


func _is_unknown(entry: Dictionary) -> bool:
	if str(entry.get("entry_type", "")) == "environment":
		return true
	var tier := str(entry.get("tier", "unknown"))
	var output_id := StringName(str(entry.get("output_id", "")))
	return tier == "unknown" or output_id.is_empty()


func _build_entry_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 142.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.95, 0.90, 0.79, 0.98)
	card_style.border_color = Color(0.53, 0.38, 0.24, 0.92)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_right = 10
	card_style.corner_radius_bottom_left = 10
	card.add_theme_stylebox_override("panel", card_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	layout.add_child(header)

	var pair_label := Label.new()
	pair_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair_label.add_theme_color_override("font_color", MUTED_INK_COLOR)
	pair_label.add_theme_font_size_override("font_size", 13)
	pair_label.text = _format_pair(entry)
	header.add_child(pair_label)

	var badge_frame := PanelContainer.new()
	badge_frame.add_theme_stylebox_override("panel", _build_badge_style(_get_badge_color(entry)))
	header.add_child(badge_frame)

	var badge := Label.new()
	badge.text = _format_quality_badge(entry)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.98, 0.97, 0.93, 1.0))
	badge_frame.add_child(badge)

	var output_label := Label.new()
	output_label.add_theme_font_size_override("font_size", 22)
	output_label.add_theme_color_override("font_color", INK_COLOR)
	output_label.text = str(entry.get("output_name", "Unknown"))
	layout.add_child(output_label)

	var conditions_label := Label.new()
	conditions_label.add_theme_color_override("font_color", MUTED_INK_COLOR)
	conditions_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conditions_label.text = _format_conditions(entry)
	layout.add_child(conditions_label)

	return card


func _format_pair(entry: Dictionary) -> String:
	if str(entry.get("entry_type", "")) == "environment":
		return "Environmental discovery"
	var output_name := str(entry.get("output_name", "Unknown"))
	var input_names: Array[String] = []
	for input_data: Dictionary in entry.get("inputs", []):
		var item_id := StringName(str(input_data.get("item_id", "")))
		input_names.append(_get_display_name(item_id))

	if input_names.is_empty():
		return output_name

	return "%s -> %s" % [" + ".join(input_names), output_name]


func _format_conditions(entry: Dictionary) -> String:
	if str(entry.get("entry_type", "")) == "environment":
		return str(entry.get("notes", ""))
	if str(entry.get("entry_type", "")) == "chem_bench":
		return str(entry.get("notes", ""))
	var output_id := StringName(str(entry.get("output_id", "")))
	var notes := str(entry.get("notes", ""))
	var temperature := int(round(float(entry.get("temperature", 0.0))))
	var input_ids: Array[StringName] = []
	for input_data: Dictionary in entry.get("inputs", []):
		input_ids.append(StringName(str(input_data.get("item_id", ""))))

	if input_ids.size() == 1 and input_ids[0] == &"wood":
		if output_id == &"charcoal":
			return "Conditions: 400-699°C carbonisation window. Logged at %d°C." % temperature
		if output_id == &"slag":
			return "Conditions: 700°C or higher overburns the wood. Logged at %d°C." % temperature

	if notes.is_empty():
		return "Conditions: logged at %d°C." % temperature
	return "Conditions: %s Logged at %d°C." % [notes, temperature]


func _format_quality_badge(entry: Dictionary) -> String:
	if str(entry.get("entry_type", "")) == "environment":
		return "Field Note"
	var tier := str(entry.get("tier", "unknown")).capitalize()
	var quality_pct := int(round(float(entry.get("quality", 0.0)) * 100.0))
	return "%s %d%%" % [tier, quality_pct]


func _get_display_name(item_id: StringName) -> String:
	if item_id.is_empty():
		return "Unknown"
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get("display_name", String(item_id).capitalize()))
	return String(item_id).replace("_", " ").capitalize()


func _get_badge_color(entry: Dictionary) -> Color:
	if str(entry.get("entry_type", "")) == "environment":
		return Color(0.40, 0.32, 0.16, 1.0)
	match str(entry.get("tier", "unknown")):
		"optimal":
			return SUCCESS_COLOR
		"medium":
			return Color(0.55, 0.40, 0.21, 1.0)
		"low":
			return Color(0.44, 0.39, 0.24, 1.0)
		"success":
			return SUCCESS_COLOR
		"waste":
			return FAILURE_COLOR
		"danger":
			return DANGER_COLOR
		_:
			return UNKNOWN_COLOR


func _update_filter_button_states() -> void:
	for filter_id: String in _filter_buttons.keys():
		var button := _filter_buttons[filter_id]
		button.disabled = filter_id == _active_filter
		button.add_theme_stylebox_override(
			"normal",
			_build_filter_button_style(filter_id == _active_filter)
		)


func _apply_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PARCHMENT_BG
	panel_style.border_color = PARCHMENT_EDGE
	panel_style.shadow_color = PARCHMENT_SHADOW
	panel_style.shadow_size = 16
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.corner_radius_bottom_left = 18
	add_theme_stylebox_override("panel", panel_style)

	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", INK_COLOR)
	subtitle_label.add_theme_color_override("font_color", MUTED_INK_COLOR)
	footer_label.add_theme_color_override("font_color", MUTED_INK_COLOR)

	for button in _filter_buttons.values():
		button.add_theme_color_override("font_color", INK_COLOR)
		button.add_theme_color_override("font_hover_color", INK_COLOR)
		button.add_theme_color_override("font_pressed_color", INK_COLOR)
		button.add_theme_color_override("font_disabled_color", INK_COLOR)
		button.custom_minimum_size = Vector2(0.0, 34.0)


func _build_filter_button_style(is_active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.76, 0.64, 0.46, 1.0) if is_active else Color(0.87, 0.79, 0.64, 1.0)
	style.border_color = PARCHMENT_EDGE
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style


func _build_badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 8.0
	style.content_margin_top = 4.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 4.0
	return style
