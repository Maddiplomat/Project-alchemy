extends Panel

signal close_requested

const TAB_DISCOVERIES := 0
const TAB_ACTIVE_RESEARCH := 1
const TAB_HAZARDS := 2
const TAB_RECIPES := 3

@onready var title_label: Label = $MarginContainer/Root/TitleRow/TitleLabel
@onready var subtitle_label: Label = $MarginContainer/Root/TitleRow/SubtitleLabel
@onready var tab_bar: TabBar = $MarginContainer/Root/TabBar
@onready var entry_list: ItemList = $MarginContainer/Root/Content/Split/ListFrame/ListMargin/EntryList
@onready var detail_title_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/DetailTitleLabel
@onready var unlock_chain_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/UnlockChainLabel
@onready var try_next_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/TryNextLabel
@onready var hazard_notes_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/HazardNotesLabel
@onready var scanner_clue_label: Label = $MarginContainer/Root/Content/Split/DetailFrame/DetailMargin/DetailContent/ScannerClueLabel

var _entries: Array[Dictionary] = []


func _ready() -> void:
	_configure_tabs()
	_wire_events()
	_refresh()


func show_panel() -> void:
	visible = true
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


func _configure_tabs() -> void:
	tab_bar.clear_tabs()
	tab_bar.add_tab("Discoveries")
	tab_bar.add_tab("Active Research")
	tab_bar.add_tab("Hazards")
	tab_bar.add_tab("Recipes")


func _wire_events() -> void:
	tab_bar.tab_changed.connect(_on_tab_changed)
	entry_list.item_selected.connect(_on_entry_selected)
	if DiscoveryJournal != null and DiscoveryJournal.has_signal("journal_entry_added"):
		DiscoveryJournal.journal_entry_added.connect(_on_journal_changed)
	if DiscoveryJournal != null and DiscoveryJournal.has_signal("journal_entry_updated"):
		DiscoveryJournal.journal_entry_updated.connect(_on_journal_changed)
	if ResearchObjectives != null:
		ResearchObjectives.objective_completed.connect(_on_objectives_changed)
		ResearchObjectives.objective_activated.connect(_on_objectives_changed)
		ResearchObjectives.objective_progressed.connect(_on_objective_progressed)
		if ResearchObjectives.has_signal("objectives_restored"):
			ResearchObjectives.objectives_restored.connect(_on_objectives_restored)
	if RecipeDatabase != null and RecipeDatabase.has_signal("recipe_unlocked"):
		RecipeDatabase.recipe_unlocked.connect(_on_recipe_unlocked)


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
	subtitle_label.text = "Press J to close. Track discoveries, research, hazards, and recipes."
	_entries = _build_entries_for_tab(tab_bar.current_tab)
	_refresh_list()
	_refresh_detail(0 if not _entries.is_empty() else -1)


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
	if DiscoveryJournal == null or not DiscoveryJournal.has_method("get_entries"):
		return result

	var entries: Array[Dictionary] = DiscoveryJournal.get_entries()
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
	if ResearchObjectives == null or not ResearchObjectives.has_method("get_all_objectives"):
		return result

	var objectives: Array[Dictionary] = ResearchObjectives.get_all_objectives()
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
	if DiscoveryJournal == null or not DiscoveryJournal.has_method("get_entries"):
		return result

	var entries: Array[Dictionary] = DiscoveryJournal.get_entries()
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
	if RecipeDatabase == null or not RecipeDatabase.has_method("get_all_unlocked"):
		return result

	var recipes: Array[Dictionary] = RecipeDatabase.get_all_unlocked()
	for recipe: Dictionary in recipes:
		var output: Dictionary = recipe.get(&"output", {})
		var output_id: StringName = StringName(output.get(&"item_id", output.get(&"id", &"")))
		var title: String = str(recipe.get(&"name", _format_item_name(StringName(recipe.get(&"id", &"")))))
		var try_next: String = _build_recipe_try_next(recipe)
		var hazard_notes: String = ""
		var scanner_clue: String = ""
		if DiscoveryJournal != null and DiscoveryJournal.has_method("get_entry"):
			var journal_entry: Dictionary = DiscoveryJournal.get_entry(output_id)
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
		if RecipeDatabase != null and RecipeDatabase.has_method("get_recipe"):
			var recipe: Dictionary = RecipeDatabase.get_recipe(recipe_id)
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
	if station_id.is_empty() or RecipeDatabase.is_inventory_station(station_id):
		return "inventory"
	return _format_item_name(station_id)
