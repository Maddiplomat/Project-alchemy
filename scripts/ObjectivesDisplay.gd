class_name ObjectivesDisplay
extends Node

var panel: Panel
var collapse_button: Button
var title_label: Label
var labels: Array[Label] = []
var collapsed := false
var panel_visible := true


func configure(objectives_panel: Panel, button: Button, title: Label, objective_labels: Array[Label]) -> void:
	panel = objectives_panel
	collapse_button = button
	title_label = title
	labels = objective_labels


func set_collapsed(value: bool) -> void:
	collapsed = value
	_refresh_collapse_state()


func toggle_collapsed() -> bool:
	set_collapsed(not collapsed)
	refresh()
	return collapsed


func refresh() -> void:
	var lines: Array[String] = []
	var service := EventBus.get_research_objectives()
	if service != null and service.has_method("get_all_objectives"):
		var objectives: Array[Dictionary] = service.get_all_objectives()
		for objective in objectives:
			if bool(objective.get(&"completed", false)):
				continue
			var prefix := "[Active] " if bool(objective.get(&"active", false)) else "[Queued] "
			var line := prefix + str(objective.get(&"title", "Untitled Objective"))
			var target := int(objective.get(&"condition_count", 0))
			if target > 1:
				line += " (%d/%d)" % [clampi(int(objective.get(&"progress", 0)), 0, target), target]
			var hint := str(objective.get(&"hint", ""))
			if not hint.is_empty():
				line += " - " + hint
			lines.append(line)
			if lines.size() >= labels.size():
				break
	title_label.text = "Objectives (%d)" % lines.size() if collapsed else "Research Objectives"
	for index in labels.size():
		labels[index].text = lines[index] if index < lines.size() else ("No active objectives" if index == 0 else "")
	panel.visible = panel_visible
	_refresh_collapse_state()


func _refresh_collapse_state() -> void:
	for label in labels:
		label.visible = not collapsed
	collapse_button.text = "+" if collapsed else "-"
