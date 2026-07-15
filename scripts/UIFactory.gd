class_name UIFactory
extends RefCounted

## Shared UI resource access. Duplicate a theme style only when a caller needs
## a per-instance color variation; static UI should use game_theme.tres directly.

const GAME_THEME: Theme = preload("res://assets/themes/game_theme.tres")


static func panel_style() -> StyleBoxFlat:
	return _duplicate_style(&"panel", &"PanelContainer")


static func button_style() -> StyleBoxFlat:
	return _duplicate_style(&"normal", &"Button")


static func _duplicate_style(style_name: StringName, theme_type: StringName) -> StyleBoxFlat:
	var source := GAME_THEME.get_stylebox(style_name, theme_type) as StyleBoxFlat
	if source == null:
		push_error("Missing %s style '%s' in game_theme.tres." % [theme_type, style_name])
		return null
	return source.duplicate() as StyleBoxFlat
