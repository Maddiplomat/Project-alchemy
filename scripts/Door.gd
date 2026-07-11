extends "res://scripts/PlacedObject.gd"

const TILE_SIZE := 16
const DOOR_WOOD := Color(0.47, 0.29, 0.15, 1.0)
const DOOR_WOOD_DARK := Color(0.30, 0.18, 0.09, 1.0)
const DOOR_STONE := Color(0.60, 0.62, 0.68, 1.0)
const DOOR_SHADOW := Color(0.18, 0.20, 0.24, 1.0)
const DOOR_OPEN_ALPHA := 0.45
const INTERACT_RANGE := 20.0

@export var is_open := false

@onready var prompt_label: Label = $PromptLabel

var _player_in_range := false
var _player: Node = null
var _interact_locked_until_release := false


func _ready() -> void:
	object_type = "door"
	save_bucket = SaveBucket.WALLS
	super()
	add_to_group(&"placed_doors")
	_build_door_texture()
	_apply_door_state()
	_configure_prompt_label()
	_hide_prompt()
	call_deferred("_refresh_adjacent_walls")


func _process(_delta: float) -> void:
	_refresh_player_range_state()

	if _interact_locked_until_release:
		if not Input.is_action_pressed("interact"):
			_interact_locked_until_release = false
		return

	if _player_in_range and Input.is_action_just_pressed("interact"):
		_toggle_door()


func _toggle_door() -> void:
	if is_open:
		if not _can_close_door():
			_show_prompt(true, "Blocked")
			_interact_locked_until_release = true
			return
		is_open = false
	else:
		is_open = true

	_apply_door_state()
	GameManager.mark_dirty()
	_interact_locked_until_release = true


func _apply_door_state() -> void:
	if collision_shape != null:
		collision_shape.disabled = is_open
	if sprite != null:
		sprite.modulate = Color(1.0, 1.0, 1.0, DOOR_OPEN_ALPHA) if is_open else Color.WHITE
		sprite.rotation_degrees = 12.0 if is_open else 0.0
		sprite.offset = Vector2(1.0, 0.0) if is_open else Vector2.ZERO
	_show_prompt(_player_in_range)


func _can_close_door() -> bool:
	if collision_shape == null or collision_shape.shape == null:
		return true

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1
	query.exclude = [get_rid()]

	for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var collider := hit.get("collider") as Node
		if collider != null:
			return false
	return true


func _build_door_texture() -> void:
	if sprite == null:
		return

	var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(1, 15):
		for x in range(3, 13):
			image.set_pixel(x, y, DOOR_WOOD if ((x / 3) + (y / 4)) % 2 == 0 else DOOR_WOOD_DARK)

	for x in range(2, 14):
		image.set_pixel(x, 0, DOOR_STONE)
		image.set_pixel(x, 15, DOOR_SHADOW)

	for y in range(1, 15):
		image.set_pixel(2, y, DOOR_STONE)
		image.set_pixel(13, y, DOOR_SHADOW)

	for y in range(4, 12):
		image.set_pixel(7, y, DOOR_STONE)

	image.set_pixel(10, 8, Color(0.84, 0.72, 0.42, 1.0))

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2.ZERO


func _configure_prompt_label() -> void:
	if prompt_label == null:
		return
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.offset_left = -46.0
	prompt_label.offset_top = -34.0
	prompt_label.offset_right = 46.0
	prompt_label.offset_bottom = -10.0


func _refresh_player_range_state() -> void:
	var player := _get_player()
	if player == null:
		_player = null
		_player_in_range = false
		_hide_prompt()
		return

	_player = player
	_player_in_range = global_position.distance_to(player.global_position) <= INTERACT_RANGE
	if _player_in_range:
		_show_prompt(true)
	else:
		_hide_prompt()


func _show_prompt(should_show: bool, override_text: String = "") -> void:
	if prompt_label == null:
		return
	prompt_label.visible = should_show
	if not should_show:
		return
	if not override_text.is_empty():
		prompt_label.text = override_text
		return
	prompt_label.text = _get_prompt_text()


func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.visible = false


func _get_prompt_text() -> String:
	var action_text := "Close" if is_open else "Open"
	return "Tap Interact to %s" % action_text if MobileInputRouter.prefers_touch_controls() else "Press E to %s" % action_text


func _get_player() -> CharacterBody2D:
	return GameManager.get_player() as CharacterBody2D


func to_world_save_entry() -> Dictionary:
	var entry := super.to_world_save_entry()
	entry[&"is_open"] = is_open
	return entry


func restore_from_pickup(data: Dictionary) -> void:
	is_open = bool(data.get(&"is_open", is_open))
	_apply_door_state()
	call_deferred("_refresh_adjacent_walls")


func get_placed_tile_coords() -> Vector2i:
	return placed_at


func _refresh_adjacent_walls() -> void:
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var tile_coords: Vector2i = placed_at + offset
		for node in get_tree().get_nodes_in_group(&"placed_walls"):
			if not is_instance_valid(node):
				continue
			if node.has_method("get_placed_tile_coords") and node.call("get_placed_tile_coords") == tile_coords:
				if node.has_method("refresh_wall_and_neighbors"):
					node.call("refresh_wall_and_neighbors")
