extends Panel

const GameplayData = preload("res://scripts/GameplayData.gd")

signal close_requested

const TAB_DISCOVERIES := 0
const TAB_ACTIVE_RESEARCH := 1
const TAB_HAZARDS := 2
const TAB_RECIPES := 3

@onready var title_label: Label = $MarginContainer/Root/HeaderRow/TitleRow/TitleLabel
@onready var subtitle_label: Label = $MarginContainer/Root/HeaderRow/TitleRow/SubtitleLabel
@onready var close_button: Button = $MarginContainer/Root/HeaderRow/CloseButton
@onready var tab_bar: TabBar = $MarginContainer/Root/TabBar
@onready var split_container: BoxContainer = $MarginContainer/Root/Content/Split
@onready var entry_list: ItemList = $MarginContainer/Root/Content/Split/ListFrame/ListMargin/EntryList
@onready var detail_title_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/DetailTitleLabel
@onready var unlock_chain_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/UnlockChainLabel
@onready var try_next_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/TryNextLabel
@onready var hazard_notes_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/HazardNotesLabel
@onready var scanner_clue_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/ScannerClueLabel

var _entries: Array[Dictionary] = []
var _touch_layout_applied := false


func _ready() -> void:
	_configure_tabs()
	_wire_events()
	get_viewport().size_changed.connect(_apply_layout)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	_apply_layout()
	_refresh()


func show_panel() -> void:
	visible = true
	_apply_layout()
	_refresh()
	entry_list.grab_focus()


func hide_panel() -> void:
	visible = false
	release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("toggle_journal"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_requested.emit()
		get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()


func _configure_tabs() -> void:
	tab_bar.clear_tabs()
	tab_bar.add_tab("Discoveries")
	tab_bar.add_tab("Active Research")
	tab_bar.add_tab("Hazards")
	tab_bar.add_tab("Recipes")


func _wire_events() -> void:
	tab_bar.tab_changed.connect(_on_tab_changed)
	entry_list.item_selected.connect(_on_entry_selected)
	if EventBus.get_discovery_journal() != null and EventBus.get_discovery_journal().has_signal("journal_entry_added"):
		EventBus.get_discovery_journal().journal_entry_added.connect(_on_journal_changed)
	if EventBus.get_discovery_journal() != null and EventBus.get_discovery_journal().has_signal("journal_entry_updated"):
		EventBus.get_discovery_journal().journal_entry_updated.connect(_on_journal_changed)
	if EventBus.get_research_objectives() != null:
		EventBus.get_research_objectives().objective_completed.connect(_on_objectives_changed)
		EventBus.get_research_objectives().objective_activated.connect(_on_objectives_changed)
		EventBus.get_research_objectives().objective_progressed.connect(_on_objective_progressed)
		if EventBus.get_research_objectives().has_signal("objectives_restored"):
			EventBus.get_research_objectives().objectives_restored.connect(_on_objectives_restored)
	if GameplayData.recipes() != null and GameplayData.recipes().has_signal("recipe_unlocked"):
		GameplayData.recipes().recipe_unlocked.connect(_on_recipe_unlocked)


func _on_tab_changed(_tab: int) -> void:
	_refresh()


func _on_journal_changed(_entry: Dictionary) -> void:
	if visible:
		_refresh()


func _on_objectives_changed(_objective_id: StringName) -> void:
	if visible and tab_bar.current_tab == TAB_ACTIVE_RESEARCH:
		_refresh()


func _on_objective_progressed(_objective_id: StringName, _current: int, _target: int) -> void:
	if visible and tab_bar.current_tab == TAB_ACTIVE_RESEARCH:
		_refresh()


func _on_objectives_restored() -> void:
	if visible and tab_bar.current_tab == TAB_ACTIVE_RESEARCH:
		_refresh()


func _on_recipe_unlocked(_recipe_id: StringName) -> void:
	if visible and tab_bar.current_tab == TAB_RECIPES:
		_refresh()


func _refresh() -> void:
	title_label.text = "Field Journal"
	subtitle_label.text = "Track discoveries, research, hazards, and recipes. Use Close or Journal to dismiss."
	_entries = _build_entries_for_tab(tab_bar.current_tab)
	_refresh_list()
	_refresh_detail(0 if not _entries.is_empty() else -1)


func _apply_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var touch_mode := MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()
	var safe_insets := _get_safe_insets(viewport_size)
	var inset_left := float(safe_insets.get(&"left", 0.0))
	var inset_top := float(safe_insets.get(&"top", 0.0))
	var inset_right := float(safe_insets.get(&"right", 0.0))
	var inset_bottom := float(safe_insets.get(&"bottom", 0.0))
	if touch_mode:
		var width := viewport_size.x - inset_left - inset_right - 20.0
		var height := viewport_size.y - inset_top - inset_bottom - 20.0
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 0.0
		anchor_bottom = 0.0
		offset_left = inset_left + 10.0
		offset_top = inset_top + 10.0
		offset_right = offset_left + maxf(320.0, width)
		offset_bottom = offset_top + maxf(420.0, height)
		split_container.vertical = true
		tab_bar.clip_tabs = true
		close_button.visible = true
		_touch_layout_applied = true
		return

	if _touch_layout_applied:
		anchor_left = 0.5
		anchor_top = 0.5
		anchor_right = 0.5
		anchor_bottom = 0.5
	offset_left = -420.0
	offset_top = -250.0
	offset_right = 420.0
	offset_bottom = 250.0
	split_container.vertical = false
	tab_bar.clip_tabs = false
	close_button.visible = true
	_touch_layout_applied = false


func _get_safe_insets(viewport_size: Vector2) -> Dictionary:
	var safe_rect := Rect2(Vector2.ZERO, viewport_size)
	if DisplayServer.has_method("get_display_safe_area"):
		var safe_area: Variant = DisplayServer.get_display_safe_area()
		if safe_area is Rect2i:
			safe_rect = Rect2(safe_area.position, safe_area.size)
		elif safe_area is Rect2:
			safe_rect = safe_area
	return {
		&"left": maxf(0.0, safe_rect.position.x),
		&"top": maxf(0.0, safe_rect.position.y),
		&"right": maxf(0.0, viewport_size.x - safe_rect.end.x),
		&"bottom": maxf(0.0, viewport_size.y - safe_rect.end.y),
	}


func _refresh_list() -> void:
	entry_list.clear()
	for entry: Dictionary in _entries:
		entry_list.add_item(str(entry.get(&"title", "Untitled")))
	if not _entries.is_empty():
		entry_list.select(0)


func _on_entry_selected(index: int) -> void:
	_refresh_detail(index)


func _refresh_detail(index: int) -> void:
	if index < 0 or index >= _entries.size():
		detail_title_label.text = "No entry selected"
		unlock_chain_label.text = "Unlock chain: None"
		try_next_label.text = "Try next: Keep scanning and experimenting."
		hazard_notes_label.text = "Hazard notes: None recorded."
		scanner_clue_label.text = "Scanner clue: No clue recorded."
		return

	var entry: Dictionary = _entries[index]
	detail_title_label.text = str(entry.get(&"title", "Untitled"))
	unlock_chain_label.text = "Unlock chain: %s" % str(entry.get(&"unlock_chain", "None"))
	try_next_label.text = "Try next: %s" % str(entry.get(&"try_next", "No hint recorded."))
	hazard_notes_label.text = "Hazard notes: %s" % str(entry.get(&"hazard_notes", "None recorded."))
	scanner_clue_label.text = "Scanner clue: %s" % str(entry.get(&"scanner_clue", "No clue recorded."))


func _build_entries_for_tab(tab_index: int) -> Array[Dictionary]:
	match tab_index:
		TAB_DISCOVERIES:
			return _build_discovery_entries()
		TAB_ACTIVE_RESEARCH:
			return _build_research_entries()
		TAB_HAZARDS:
			return _build_hazard_entries()
		TAB_RECIPES:
			return _build_recipe_entries()
		_:
			return []


func _build_discovery_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if EventBus.get_discovery_journal() == null or not EventBus.get_discovery_journal().has_method("get_entries"):
		return result

	var entries: Array[Dictionary] = EventBus.get_discovery_journal().get_entries()
	for entry: Dictionary in entries:
		result.append({
			&"title": _format_item_name(StringName(entry.get(&"element_id", &""))),
			&"unlock_chain": _format_unlock_chain(entry.get(&"unlocks_recipe", [])),
			&"try_next": str(entry.get(&"next_hint", "")),
			&"hazard_notes": str(entry.get(&"hazard_notes", "")),
			&"scanner_clue": str(entry.get(&"scanner_clue", "")),
		})
	return result


func _build_research_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if EventBus.get_research_objectives() == null or not EventBus.get_research_objectives().has_method("get_all_objectives"):
		return result

	var objectives: Array[Dictionary] = EventBus.get_research_objectives().get_all_objectives()
	for objective: Dictionary in objectives:
		if bool(objective.get(&"completed", false)):
			continue
		var title_prefix: String = "[Active] " if bool(objective.get(&"active", false)) else "[Queued] "
		var progress_text := _format_objective_progress(objective)
		result.append({
			&"title": "%s%s%s" % [title_prefix, str(objective.get(&"title", "Objective")), progress_text],
			&"unlock_chain": _format_reward_chain(objective),
			&"try_next": str(objective.get(&"hint", "")),
			&"hazard_notes": "Condition: %s%s" % [str(objective.get(&"condition_type", "")), _format_objective_progress_label(objective)],
			&"scanner_clue": "Target: %s" % String(objective.get(&"condition_target", &"")),
		})
	return result


func _format_objective_progress(objective: Dictionary) -> String:
	var target := int(objective.get(&"condition_count", 0))
	if target <= 1:
		return ""
	var current := clampi(int(objective.get(&"progress", 0)), 0, target)
	return " (%d/%d)" % [current, target]


func _format_objective_progress_label(objective: Dictionary) -> String:
	var target := int(objective.get(&"condition_count", 0))
	if target <= 1:
		return ""
	var current := clampi(int(objective.get(&"progress", 0)), 0, target)
	return " [%d/%d]" % [current, target]


func _build_hazard_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if EventBus.get_discovery_journal() == null or not EventBus.get_discovery_journal().has_method("get_entries"):
		return result

	var entries: Array[Dictionary] = EventBus.get_discovery_journal().get_entries()
	for entry: Dictionary in entries:
		var hazard_notes: String = str(entry.get(&"hazard_notes", "")).strip_edges()
		if hazard_notes.is_empty():
			continue
		result.append({
			&"title": _format_item_name(StringName(entry.get(&"element_id", &""))),
			&"unlock_chain": _format_unlock_chain(entry.get(&"unlocks_recipe", [])),
			&"try_next": str(entry.get(&"next_hint", "")),
			&"hazard_notes": hazard_notes,
			&"scanner_clue": str(entry.get(&"scanner_clue", "")),
		})
	return result


func _build_recipe_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if GameplayData.recipes() == null or not GameplayData.recipes().has_method("get_all_unlocked"):
		return result

	var recipes: Array[Dictionary] = GameplayData.recipes().get_all_unlocked()
	for recipe: Dictionary in recipes:
		var output: Dictionary = recipe.get(&"output", {})
		var output_id: StringName = StringName(output.get(&"item_id", output.get(&"id", &"")))
		var title: String = str(recipe.get(&"name", _format_item_name(StringName(recipe.get(&"id", &"")))))
		var try_next: String = _build_recipe_try_next(recipe)
		var hazard_notes: String = ""
		var scanner_clue: String = ""
		if EventBus.get_discovery_journal() != null and EventBus.get_discovery_journal().has_method("get_entry"):
			var journal_entry: Dictionary = EventBus.get_discovery_journal().get_entry(output_id)
			if not journal_entry.is_empty():
				try_next = str(journal_entry.get(&"next_hint", try_next))
				hazard_notes = str(journal_entry.get(&"hazard_notes", ""))
				scanner_clue = str(journal_entry.get(&"scanner_clue", ""))
		result.append({
			&"title": title,
			&"unlock_chain": _format_recipe_inputs(recipe.get(&"inputs", []), recipe),
			&"try_next": try_next,
			&"hazard_notes": hazard_notes if not hazard_notes.is_empty() else "No hazard notes recorded.",
			&"scanner_clue": scanner_clue if not scanner_clue.is_empty() else "No scanner clue recorded.",
		})
	return result


func _format_unlock_chain(unlocks_recipe: Array) -> String:
	var names: Array[String] = []
	for raw_recipe_id in unlocks_recipe:
		var recipe_id: StringName = StringName(raw_recipe_id)
		if recipe_id.is_empty():
			continue
		var recipe_name: String = _format_item_name(recipe_id)
		if GameplayData.recipes() != null and GameplayData.recipes().has_method("get_recipe"):
			var recipe: Dictionary = GameplayData.recipes().get_recipe(recipe_id)
			if not recipe.is_empty():
				recipe_name = str(recipe.get(&"name", recipe_name))
		names.append(recipe_name)
	return ", ".join(names) if not names.is_empty() else "None"


func _format_reward_chain(objective: Dictionary) -> String:
	var reward_type: String = str(objective.get(&"reward_type", "")).strip_edges()
	var reward_target: StringName = StringName(objective.get(&"reward_target", &""))
	if reward_type.is_empty() or reward_target.is_empty():
		return "None"
	return "%s -> %s" % [reward_type, _format_item_name(reward_target)]


func _format_recipe_inputs(inputs: Array, recipe: Dictionary = {}) -> String:
	var parts: Array[String] = []
	for input_data: Dictionary in inputs:
		var item_id: StringName = StringName(input_data.get(&"item_id", input_data.get(&"id", &"")))
		var qty: int = int(input_data.get(&"qty", input_data.get(&"quantity", 0)))
		if item_id.is_empty() or qty <= 0:
			continue
		parts.append("%s x%d" % [_format_item_name(item_id), qty])
	var base_text := ", ".join(parts) if not parts.is_empty() else "No inputs listed"
	var process_hint := str(recipe.get(&"process_hint", "")).strip_edges()
	if not process_hint.is_empty():
		return "%s. %s" % [base_text, process_hint]
	return base_text


func _build_recipe_try_next(recipe: Dictionary) -> String:
	var hints: Array[String] = []
	var station_id := StringName(recipe.get(&"station", &""))
	hints.append("Craft at %s." % _format_station(station_id))

	var temperature_hint := str(recipe.get(&"temperature_hint", "")).strip_edges()
	if not temperature_hint.is_empty():
		hints.append(temperature_hint)

	var ratio_hint := str(recipe.get(&"ratio_hint", "")).strip_edges()
	if not ratio_hint.is_empty():
		hints.append(ratio_hint)

	return " ".join(hints)


func _format_item_name(item_id: StringName) -> String:
	var raw: String = String(item_id).replace("_", " ").strip_edges()
	if raw.is_empty():
		return "Unknown"
	return raw.capitalize()


func _format_station(station_id: StringName) -> String:
	if station_id.is_empty() or GameplayData.recipes().is_inventory_station(station_id):
		return "inventory"
	return _format_item_name(station_id)
