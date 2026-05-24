extends StaticBody2D

const CHEM_BENCH_UI_SCENE := preload("res://scenes/UI/ChemBenchUI.tscn")
const CHEM_BENCH_STATION_ID := &"chem_bench"

signal player_entered_range
signal player_exited_range
signal interaction_started
signal interaction_ended

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $PromptLabel

var _player_in_range := false
var _is_interacting := false
var _interact_locked_until_release := false
var _player: Node = null
var _chem_bench_ui


func _ready() -> void:
	sprite.texture = _build_placeholder_texture()
	_apply_visual_identity()
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
		_start_interaction()


func open_ui() -> void:
	_is_interacting = true
	_interact_locked_until_release = true
	_show_prompt(false)
	if is_instance_valid(_player) and _player.has_method("pause_input"):
		_player.pause_input()
	_ensure_ui()
	if _chem_bench_ui != null:
		if _chem_bench_ui.has_method("bind_chem_bench"):
			_chem_bench_ui.bind_chem_bench(self)
		_chem_bench_ui.open_ui()
	interaction_started.emit()


func close_ui() -> void:
	if not _is_interacting:
		return

	_is_interacting = false
	_interact_locked_until_release = true
	_show_prompt(_player_in_range)
	if _chem_bench_ui != null:
		_chem_bench_ui.close_ui()
	if is_instance_valid(_player) and _player.has_method("resume_input"):
		_player.resume_input()
	interaction_ended.emit()


func get_available_recipes() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for recipe_id: StringName in RecipeDatabase.get_all_recipes().keys():
		var recipe := RecipeDatabase.get_recipe(recipe_id)
		if recipe.get(&"station", null) != CHEM_BENCH_STATION_ID:
			continue
		_apply_recipe_metadata(recipe)
		results.append(recipe)
	return results


func get_active_recipe() -> Dictionary:
	var recipes := get_available_recipes()
	return recipes[0] if not recipes.is_empty() else {}


func _start_interaction() -> void:
	open_ui()


func _on_body_entered(body: Node) -> void:
	if body.name == "Player" and body is CharacterBody2D:
		_player = body
		_player_in_range = true
		if not _is_interacting:
			_show_prompt(true)
		player_entered_range.emit()


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		if body == _player:
			_player = null
		_player_in_range = false
		_hide_prompt()
		player_exited_range.emit()


func _show_prompt(should_show: bool) -> void:
	if prompt_label != null:
		prompt_label.visible = should_show


func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.visible = false


func _ensure_ui() -> void:
	if _chem_bench_ui != null:
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var ui_parent := current_scene.find_child("HUD", true, false)
	if ui_parent == null:
		ui_parent = current_scene

	_chem_bench_ui = CHEM_BENCH_UI_SCENE.instantiate()
	ui_parent.add_child(_chem_bench_ui)
	_chem_bench_ui.ui_closed.connect(_on_ui_closed)
	if _chem_bench_ui.has_method("bind_chem_bench"):
		_chem_bench_ui.bind_chem_bench(self)


func _on_ui_closed() -> void:
	close_ui()


func _apply_visual_identity() -> void:
	sprite.offset = Vector2(0.0, -4.0)


func _apply_recipe_metadata(recipe: Dictionary) -> void:
	var recipe_id: StringName = recipe.get(&"id", &"")
	match recipe_id:
		&"rust_bolt":
			recipe[&"display_name"] = "Rust Bolt"
			recipe[&"summary"] = "Oxidize iron with water to produce throwable rust bolts."
		&"iron_sword":
			recipe[&"display_name"] = "Iron Sword"
			recipe[&"summary"] = "Forge an iron blade with a simple wooden grip."


func _build_placeholder_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for y in range(12, 24):
		for x in range(3, 29):
			image.set_pixel(x, y, Color(0.24, 0.18, 0.12, 1.0))

	for y in range(8, 13):
		for x in range(5, 27):
			image.set_pixel(x, y, Color(0.34, 0.27, 0.18, 1.0))

	for y in range(5, 8):
		for x in range(10, 15):
			image.set_pixel(x, y, Color(0.45, 0.62, 0.58, 0.95))
		for x in range(18, 23):
			image.set_pixel(x, y, Color(0.56, 0.42, 0.18, 0.95))

	for y in range(24, 31):
		for x in range(6, 10):
			image.set_pixel(x, y, Color(0.18, 0.12, 0.08, 1.0))
		for x in range(22, 26):
			image.set_pixel(x, y, Color(0.18, 0.12, 0.08, 1.0))

	return ImageTexture.create_from_image(image)
