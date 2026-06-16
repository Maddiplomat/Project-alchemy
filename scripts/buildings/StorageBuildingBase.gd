extends "res://scripts/PlacedObject.gd"

const STORAGE_UI_SCENE := preload("res://scenes/UI/StorageUI.tscn")

@export var container_id: StringName = &""

@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $PromptLabel

var _player_in_range := false
var _player: Node = null
var _ui
var _is_interacting := false
var _interact_locked_until_release := false


func _ready() -> void:
	object_type = _get_object_type()
	save_bucket = SaveBucket.STORAGE
	if container_id.is_empty():
		container_id = StorageManager.generate_chest_id()
	_ensure_storage_container()
	_build_storage_texture()
	super()
	_configure_prompt_label()
	call_deferred("_ensure_ui")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_hide_prompt()


func _process(_delta: float) -> void:
	if _interact_locked_until_release:
		if not Input.is_action_pressed("interact"):
			_interact_locked_until_release = false
		return
	if _player_in_range and not _is_interacting and Input.is_action_just_pressed("interact"):
		open_ui()


func open_ui() -> void:
	_is_interacting = true
	_interact_locked_until_release = true
	_show_prompt(false)
	if is_instance_valid(_player) and _player.has_method("pause_input"):
		_player.pause_input()
	_ensure_ui()
	if _ui != null:
		if _ui.has_method("bind_chest"):
			_ui.bind_chest(container_id)
		_ui.open_ui()


func close_ui() -> void:
	if not _is_interacting:
		return
	_is_interacting = false
	_interact_locked_until_release = true
	_show_prompt(_player_in_range)
	if _ui != null:
		_ui.close_ui()
	if is_instance_valid(_player) and _player.has_method("resume_input"):
		_player.resume_input()


func to_world_save_entry() -> Dictionary:
	var entry := super.to_world_save_entry()
	entry[&"container_id"] = container_id
	return entry


func restore_from_pickup(entry: Dictionary) -> void:
	var restored_id := StringName(str(entry.get(&"container_id", container_id)))
	if not restored_id.is_empty():
		container_id = restored_id
	_ensure_storage_container()
	if _ui != null and _ui.has_method("bind_chest"):
		_ui.bind_chest(container_id)


func _ensure_storage_container() -> void:
	StorageManager.ensure_container(container_id, {
		&"slot_count": _get_slot_count(),
		&"title": _get_container_title(),
		&"filter_id": _get_storage_filter_id(),
	})


func _ensure_ui() -> void:
	if _ui != null:
		return
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var ui_parent := current_scene.find_child("HUD", true, false)
	if ui_parent == null:
		ui_parent = current_scene
	_ui = STORAGE_UI_SCENE.instantiate()
	ui_parent.add_child(_ui)
	_ui.ui_closed.connect(_on_ui_closed)
	if _ui.has_method("bind_chest"):
		_ui.bind_chest(container_id)


func _on_ui_closed() -> void:
	close_ui()


func _on_body_entered(body: Node) -> void:
	if body.name == "Player" and body is CharacterBody2D:
		_player = body
		_player_in_range = true
		if not _is_interacting:
			_show_prompt(true)


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
	_player_in_range = false
	_hide_prompt()


func _show_prompt(should_show: bool) -> void:
	if prompt_label != null:
		prompt_label.visible = should_show
		if should_show:
			prompt_label.text = _get_prompt_text()


func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.visible = false


func _configure_prompt_label() -> void:
	if prompt_label == null:
		return
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.offset_left = -84.0
	prompt_label.offset_top = -42.0
	prompt_label.offset_right = 84.0
	prompt_label.offset_bottom = -8.0


func _get_object_type() -> String:
	return "storage_building"


func _get_container_title() -> String:
	return "Storage"


func _get_prompt_text() -> String:
	return "Press E to open Storage"


func _get_storage_filter_id() -> StringName:
	return StorageManager.FILTER_ANY


func _get_slot_count() -> int:
	return 8


func _build_storage_texture() -> void:
	pass
