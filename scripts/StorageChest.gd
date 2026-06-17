extends "res://scripts/PlacedObject.gd"

const STORAGE_UI_SCENE := preload("res://scenes/UI/StorageUI.tscn")
const CHEST_WOOD := Color(0.45, 0.27, 0.14, 1.0)
const CHEST_WOOD_DARK := Color(0.29, 0.18, 0.10, 1.0)
const CHEST_METAL := Color(0.75, 0.68, 0.42, 1.0)

@export var chest_id: StringName = &""

@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $PromptLabel

var _player_in_range := false
var _player: Node = null
var _ui
var _is_interacting := false
var _interact_locked_until_release := false


func _ready() -> void:
	object_type = "storage_chest"
	save_bucket = SaveBucket.STORAGE
	if chest_id.is_empty():
		chest_id = StorageManager.generate_chest_id()
	StorageManager.ensure_container(chest_id, {
		&"slot_count": StorageManager.DEFAULT_SLOT_COUNT,
		&"title": "Storage Chest",
		&"filter_id": StorageManager.FILTER_ANY,
	})
	_build_chest_texture()
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
			_ui.bind_chest(chest_id)
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
	entry[&"chest_id"] = chest_id
	return entry


func restore_from_pickup(entry: Dictionary) -> void:
	var restored_id := StringName(str(entry.get(&"chest_id", chest_id)))
	if not restored_id.is_empty():
		chest_id = restored_id
	StorageManager.ensure_container(chest_id, {
		&"slot_count": StorageManager.DEFAULT_SLOT_COUNT,
		&"title": "Storage Chest",
		&"filter_id": StorageManager.FILTER_ANY,
	})
	if _ui != null and _ui.has_method("bind_chest"):
		_ui.bind_chest(chest_id)


func _build_chest_texture() -> void:
	if sprite == null:
		return

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(12, 24):
		for x in range(5, 27):
			image.set_pixel(x, y, CHEST_WOOD)

	for y in range(24, 29):
		for x in range(7, 25):
			image.set_pixel(x, y, CHEST_WOOD_DARK)

	for x in range(5, 27):
		image.set_pixel(x, 12, CHEST_METAL)
		image.set_pixel(x, 18, CHEST_METAL)

	for y in range(12, 24):
		image.set_pixel(15, y, CHEST_METAL)
		image.set_pixel(16, y, CHEST_METAL)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2(0.0, -2.0)


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
		_ui.bind_chest(chest_id)


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
			prompt_label.text = "Press E to open Chest"


func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.visible = false


func _configure_prompt_label() -> void:
	if prompt_label == null:
		return
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.offset_left = -66.0
	prompt_label.offset_top = -40.0
	prompt_label.offset_right = 66.0
	prompt_label.offset_bottom = -8.0
