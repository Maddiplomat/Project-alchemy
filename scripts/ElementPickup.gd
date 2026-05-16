extends Area2D

signal picked_up(item_data: Dictionary, quantity: int)

static var _shape_logged := false

@export var element_id: StringName = &""
@export var pickup_quantity := 1

@onready var prompt_label := $PromptLabel as Label
@onready var collision_shape := $CollisionShape2D as CollisionShape2D
@onready var anim_player := $AnimationPlayer as AnimationPlayer
@onready var sprite := $Sprite2D as Sprite2D
@onready var glow_sprite := $GlowSprite2D as Sprite2D

var _player_in_range: CharacterBody2D = null
var _pickup_textures := {}
var _glow_textures := {}


func _ready() -> void:
	prompt_label.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_apply_visual_identity()
	_setup_animations()
	_play_idle_animation()

	_log_shape_size_once()


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range == null or not prompt_label.visible:
		return

	if event.is_action_pressed("interact"):
		_attempt_pickup()


func _on_body_entered(body: Node) -> void:
	if not body is CharacterBody2D:
		return

	_player_in_range = body
	prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if body != _player_in_range:
		return

	_player_in_range = null
	prompt_label.visible = false


func _attempt_pickup() -> void:
	var item_data := _get_pickup_item_data()
	if item_data.is_empty():
		return

	if not InventoryManager.add_element(item_data.id, pickup_quantity, 1.0):
		return

	picked_up.emit(item_data, pickup_quantity)
	prompt_label.visible = false
	queue_free()


func _get_pickup_item_data() -> Dictionary:
	var resolved_element_id := element_id
	if resolved_element_id.is_empty():
		resolved_element_id = get_meta(&"element_id", &"")

	if resolved_element_id.is_empty():
		return {}

	return ElementDatabase.get_element(resolved_element_id)


func _log_shape_size_once() -> void:
	if _shape_logged:
		return

	var rectangle_shape := collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		return

	var runtime := get_tree().root.get_node_or_null("MCPRuntime")
	if runtime == null or not runtime.has_method("push_runtime_log"):
		return

	runtime.push_runtime_log("info", "ElementPickup collision size=%s extents=%s" % [rectangle_shape.size, rectangle_shape.size * 0.5])
	_shape_logged = true


func _setup_animations() -> void:
	var lib := AnimationLibrary.new()

	# Wood: gentle sway
	var anim_wood := Animation.new()
	anim_wood.length = 1.5
	anim_wood.loop_mode = Animation.LOOP_LINEAR
	var track_wood := anim_wood.add_track(Animation.TYPE_VALUE)
	anim_wood.track_set_path(track_wood, "Sprite2D:rotation")
	anim_wood.track_insert_key(track_wood, 0.0, 0.0)
	anim_wood.track_insert_key(track_wood, 0.375, deg_to_rad(2.0))
	anim_wood.track_insert_key(track_wood, 0.75, 0.0)
	anim_wood.track_insert_key(track_wood, 1.125, deg_to_rad(-2.0))
	anim_wood.track_insert_key(track_wood, 1.5, 0.0)
	lib.add_animation("idle_wood", anim_wood)

	# Stone: none
	var anim_stone := Animation.new()
	anim_stone.length = 1.5
	anim_stone.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle_stone", anim_stone)

	# Iron: glint pulse
	var anim_iron := Animation.new()
	anim_iron.length = 1.5
	anim_iron.loop_mode = Animation.LOOP_LINEAR
	var track_iron := anim_iron.add_track(Animation.TYPE_VALUE)
	anim_iron.track_set_path(track_iron, "Sprite2D:modulate")
	anim_iron.track_insert_key(track_iron, 0.0, Color(1, 1, 1, 1.0))
	anim_iron.track_insert_key(track_iron, 0.75, Color(1, 1, 1, 0.85))
	anim_iron.track_insert_key(track_iron, 1.5, Color(1, 1, 1, 1.0))
	lib.add_animation("idle_iron", anim_iron)

	# Charcoal: faint ember pulse.
	var anim_charcoal := Animation.new()
	anim_charcoal.length = 2.5
	anim_charcoal.loop_mode = Animation.LOOP_LINEAR
	var track_charcoal := anim_charcoal.add_track(Animation.TYPE_VALUE)
	anim_charcoal.track_set_path(track_charcoal, "GlowSprite2D:modulate")
	anim_charcoal.track_insert_key(track_charcoal, 0.0, Color(1.0, 0.46, 0.18, 0.6))
	anim_charcoal.track_insert_key(track_charcoal, 1.25, Color(1.0, 0.52, 0.22, 1.0))
	anim_charcoal.track_insert_key(track_charcoal, 2.5, Color(1.0, 0.46, 0.18, 0.6))
	lib.add_animation("idle_charcoal", anim_charcoal)

	anim_player.add_animation_library("", lib)


func _play_idle_animation() -> void:
	var resolved_element_id := element_id
	if resolved_element_id.is_empty():
		resolved_element_id = get_meta(&"element_id", &"")

	var anim_name := "idle_" + str(resolved_element_id)
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)


func get_element_id() -> StringName:
	if not element_id.is_empty():
		return element_id
	return get_meta(&"element_id", &"")


func _apply_visual_identity() -> void:
	var item_data := _get_pickup_item_data()
	var resolved_element_id := get_element_id()
	var display_name := str(item_data.get(&"display_name", resolved_element_id))
	var symbol := str(item_data.get(&"symbol", ""))

	if display_name.is_empty():
		prompt_label.text = "Press E"
	else:
		prompt_label.text = "%s (%s)" % [display_name, symbol] if not symbol.is_empty() else display_name

	sprite.texture = _get_pickup_texture(String(resolved_element_id))
	sprite.modulate = Color.WHITE
	glow_sprite.texture = null
	glow_sprite.visible = false
	glow_sprite.modulate = Color(1.0, 0.46, 0.18, 0.6)

	if resolved_element_id == &"charcoal":
		glow_sprite.texture = _get_glow_texture(String(resolved_element_id))
		glow_sprite.visible = true


func _get_pickup_texture(element_key: String) -> Texture2D:
	if _pickup_textures.has(element_key):
		return _pickup_textures[element_key]

	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	match element_key:
		"wood":
			_build_wood_texture(image)
		"stone":
			_build_stone_texture(image)
		"iron":
			_build_iron_texture(image)
		"charcoal":
			_build_charcoal_texture(image)
		_:
			_build_generic_texture(image)

	var texture := ImageTexture.create_from_image(image)
	_pickup_textures[element_key] = texture
	return texture


func _get_glow_texture(element_key: String) -> Texture2D:
	if _glow_textures.has(element_key):
		return _glow_textures[element_key]

	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	if element_key == "charcoal":
		var center := Vector2(8.0, 8.0)
		for y in range(16):
			for x in range(16):
				var distance := Vector2(float(x), float(y)).distance_to(center)
				var alpha := clampf(1.0 - (distance / 7.5), 0.0, 1.0) * 0.35
				if alpha > 0.0:
					image.set_pixel(x, y, Color(1.0, 0.48, 0.18, alpha))

	var texture := ImageTexture.create_from_image(image)
	_glow_textures[element_key] = texture
	return texture


func _build_generic_texture(image: Image) -> void:
	for y in range(4, 12):
		for x in range(4, 12):
			image.set_pixel(x, y, Color(0.88, 0.88, 0.88, 1.0))


func _build_wood_texture(image: Image) -> void:
	var bark := Color(0.49, 0.31, 0.16, 1.0)
	var highlight := Color(0.65, 0.44, 0.24, 1.0)
	for y in range(4, 12):
		for x in range(3, 13):
			image.set_pixel(x, y, bark)
	for x in range(4, 12, 2):
		for y in range(4, 12):
			image.set_pixel(x, y, highlight)


func _build_stone_texture(image: Image) -> void:
	var body := Color(0.50, 0.52, 0.55, 1.0)
	var edge := Color(0.68, 0.70, 0.73, 1.0)
	for y in range(3, 13):
		for x in range(3, 13):
			if abs(x - 8) + abs(y - 8) <= 7:
				image.set_pixel(x, y, body)
	for pos in [Vector2i(6, 5), Vector2i(9, 6), Vector2i(7, 9), Vector2i(10, 10)]:
		image.set_pixel(pos.x, pos.y, edge)


func _build_iron_texture(image: Image) -> void:
	var metal := Color(0.71, 0.74, 0.79, 1.0)
	var shadow := Color(0.46, 0.50, 0.56, 1.0)
	for y in range(4, 12):
		for x in range(4, 12):
			image.set_pixel(x, y, metal)
	for y in range(4, 12):
		image.set_pixel(4, y, shadow)
	for x in range(4, 12):
		image.set_pixel(x, 11, shadow)


func _build_charcoal_texture(image: Image) -> void:
	var body := Color(0.16, 0.17, 0.19, 1.0)
	var shadow := Color(0.08, 0.08, 0.09, 1.0)
	var highlight := Color(0.24, 0.25, 0.28, 1.0)
	var ember := Color(1.0, 0.49, 0.18, 1.0)

	var lump_pixels := [
		Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4),
		Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5),
		Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6), Vector2i(10, 6), Vector2i(11, 6),
		Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7), Vector2i(10, 7),
		Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8),
		Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9), Vector2i(9, 9),
	]

	for pixel: Vector2i in lump_pixels:
		image.set_pixel(pixel.x, pixel.y, body)

	for pixel: Vector2i in [Vector2i(5, 3), Vector2i(6, 3), Vector2i(4, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(4, 8), Vector2i(5, 9)]:
		image.set_pixel(pixel.x, pixel.y, highlight)

	for pixel: Vector2i in [Vector2i(10, 4), Vector2i(11, 5), Vector2i(11, 6), Vector2i(10, 8), Vector2i(9, 9), Vector2i(8, 9)]:
		image.set_pixel(pixel.x, pixel.y, shadow)

	for pixel: Vector2i in [Vector2i(7, 5), Vector2i(8, 6), Vector2i(6, 7)]:
		image.set_pixel(pixel.x, pixel.y, ember)
