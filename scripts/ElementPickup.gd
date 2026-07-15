extends Area2D

const GameplayData = preload("res://scripts/GameplayData.gd")
const WeatherSystem = preload("res://scripts/WeatherSystem.gd")

signal picked_up(item_data: Dictionary, quantity: int)

static var _shape_logged := false
const DISTILLATION_KIT_ITEM_ID := &"distillation_kit"
const DISTILLATION_KIT_DURABILITY_LOSS := 0.05
const SULFUR_ACID_MIST_DEGRADE_INTERVAL_SECONDS := 1.0
const SULFUR_ACID_MIST_PURITY_LOSS_PER_TICK := 0.08
const RAIN_DEGRADE_INTERVAL_SECONDS := 6.0
const RAIN_PURITY_LOSS_PER_TICK := 0.10
const RAIN_LITHIUM_CHARGE_LOSS_PER_TICK := 0.25
const RAIN_STACK_LOSS_PURITY_THRESHOLD := 0.20

@export var element_id: StringName = &""
@export var pickup_quantity := 1

@onready var prompt_label := $PromptLabel as Label
@onready var collision_shape := $CollisionShape2D as CollisionShape2D
@onready var anim_player := $AnimationPlayer as AnimationPlayer
@onready var sprite := $Sprite2D as Sprite2D
@onready var glow_sprite := $GlowSprite2D as Sprite2D
@onready var sulfur_particles := $SulfurParticles as GPUParticles2D

var _player_in_range: CharacterBody2D = null
var _pickup_textures := {}
var _glow_textures := {}
var _acid_mist_degrade_timer: Timer = null
var _rain_degrade_timer: Timer = null


func _ready() -> void:
	prompt_label.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_apply_visual_identity()
	_setup_animations()
	_play_idle_animation()
	_setup_weather_reactivity()

	_log_shape_size_once()


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range == null:
		return

	if event.is_action_pressed("interact"):
		_attempt_pickup()
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if not body is CharacterBody2D:
		return

	_player_in_range = body
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if body != _player_in_range:
		return

	_player_in_range = null
	prompt_label.visible = false


func _attempt_pickup() -> void:
	var item_data := _get_pickup_item_data()
	if item_data.is_empty():
		return

	if not _can_extract_pickup(item_data):
		prompt_label.visible = false
		return

	if not InventoryManager.receive_world_pickup(item_data, pickup_quantity):
		return

	_apply_extraction_cost(item_data)

	picked_up.emit(item_data, pickup_quantity)
	prompt_label.visible = false
	queue_free()


func _setup_weather_reactivity() -> void:
	_ensure_pickup_payload()
	if EventBus.get_weather_system() != null and EventBus.get_weather_system().has_signal("weather_changed"):
		EventBus.get_weather_system().weather_changed.connect(_on_weather_changed)
	_acid_mist_degrade_timer = Timer.new()
	_acid_mist_degrade_timer.one_shot = true
	_acid_mist_degrade_timer.wait_time = SULFUR_ACID_MIST_DEGRADE_INTERVAL_SECONDS
	_acid_mist_degrade_timer.timeout.connect(_on_acid_mist_degrade_timeout)
	add_child(_acid_mist_degrade_timer)
	_rain_degrade_timer = Timer.new()
	_rain_degrade_timer.one_shot = true
	_rain_degrade_timer.wait_time = RAIN_DEGRADE_INTERVAL_SECONDS
	_rain_degrade_timer.timeout.connect(_on_rain_degrade_timeout)
	add_child(_rain_degrade_timer)
	if EventBus.get_weather_system() != null and EventBus.get_weather_system().has_method("get_current_state"):
		_on_weather_changed(int(EventBus.get_weather_system().get_current_state()))


func _on_weather_changed(new_state: int) -> void:
	if get_element_id() == &"sulfur" and new_state == WeatherSystem.WeatherState.ACID_MIST:
		if _acid_mist_degrade_timer != null and _acid_mist_degrade_timer.is_stopped():
			_acid_mist_degrade_timer.start()
	elif _acid_mist_degrade_timer != null:
		_acid_mist_degrade_timer.stop()
	if _is_rain_vulnerable() and new_state == WeatherSystem.WeatherState.RAIN:
		if _rain_degrade_timer != null and _rain_degrade_timer.is_stopped():
			_rain_degrade_timer.start()
	elif _rain_degrade_timer != null:
		_rain_degrade_timer.stop()


func _on_acid_mist_degrade_timeout() -> void:
	if get_element_id() != &"sulfur":
		return
	if EventBus.get_weather_system() == null or not EventBus.get_weather_system().has_method("get_current_state"):
		return
	if int(EventBus.get_weather_system().get_current_state()) != WeatherSystem.WeatherState.ACID_MIST:
		return

	var item_data := _ensure_pickup_payload()
	var current_purity := clampf(float(item_data.get(&"purity", InventoryManager.DEFAULT_ITEM_PURITY)), 0.0, 1.0)
	var next_purity := clampf(current_purity - SULFUR_ACID_MIST_PURITY_LOSS_PER_TICK, 0.0, 1.0)
	item_data[&"purity"] = next_purity
	set_meta(&"item_data", item_data)
	_apply_weather_degradation_visuals(next_purity)

	if next_purity <= 0.0:
		queue_free()
		return

	_acid_mist_degrade_timer.start()


func _on_rain_degrade_timeout() -> void:
	if not _is_rain_vulnerable():
		return
	if EventBus.get_weather_system() == null or not EventBus.get_weather_system().has_method("get_current_state"):
		return
	if int(EventBus.get_weather_system().get_current_state()) != WeatherSystem.WeatherState.RAIN:
		return
	if _is_sheltered_from_rain():
		_rain_degrade_timer.start()
		return

	var item_data := _ensure_pickup_payload()
	var item_id := get_element_id()
	var current_purity := clampf(float(item_data.get(&"purity", InventoryManager.DEFAULT_ITEM_PURITY)), 0.0, 1.0)
	var next_purity := clampf(current_purity - RAIN_PURITY_LOSS_PER_TICK, 0.0, 1.0)
	item_data[&"purity"] = next_purity
	if item_id == &"lithium":
		var current_charge := clampf(float(item_data.get(&"charge", InventoryManager.DEFAULT_LITHIUM_CHARGE)), 0.0, 1.0)
		item_data[&"charge"] = clampf(current_charge - RAIN_LITHIUM_CHARGE_LOSS_PER_TICK, 0.0, 1.0)
	set_meta(&"item_data", item_data)
	_apply_weather_degradation_visuals(next_purity)

	var lithium_depleted := item_id == &"lithium" and float(item_data.get(&"charge", 0.0)) <= 0.0
	if next_purity <= RAIN_STACK_LOSS_PURITY_THRESHOLD or lithium_depleted:
		pickup_quantity -= 1
		if pickup_quantity <= 0:
			queue_free()
			return
		item_data[&"purity"] = maxf(next_purity, 0.45)
		if item_id == &"lithium":
			item_data[&"charge"] = maxf(float(item_data.get(&"charge", 0.0)), 0.25)
		set_meta(&"item_data", item_data)
		_apply_weather_degradation_visuals(float(item_data.get(&"purity", next_purity)))

	_rain_degrade_timer.start()


func _ensure_pickup_payload() -> Dictionary:
	var stored_item_data = get_meta(&"item_data", {})
	if stored_item_data is Dictionary and not stored_item_data.is_empty():
		var existing_payload := (stored_item_data as Dictionary).duplicate(true)
		if not existing_payload.has(&"purity"):
			existing_payload[&"purity"] = InventoryManager.DEFAULT_ITEM_PURITY
			set_meta(&"item_data", existing_payload)
		return existing_payload

	var generated_payload := _get_pickup_item_data()
	if generated_payload.is_empty():
		generated_payload = {&"id": get_element_id()}
	generated_payload[&"id"] = StringName(generated_payload.get(&"id", get_element_id()))
	generated_payload[&"purity"] = clampf(
		float(generated_payload.get(&"purity", InventoryManager.DEFAULT_ITEM_PURITY)),
		0.0,
		1.0
	)
	set_meta(&"item_data", generated_payload)
	return generated_payload.duplicate(true)


func _apply_weather_degradation_visuals(purity: float) -> void:
	var purity_alpha := lerpf(0.35, 1.0, clampf(purity, 0.0, 1.0))
	sprite.modulate = Color(1.0, 1.0, 1.0, purity_alpha)
	if glow_sprite != null and glow_sprite.visible:
		glow_sprite.modulate.a = purity_alpha * 0.7
	if sulfur_particles != null:
		sulfur_particles.amount_ratio = maxf(0.25, purity)


func _is_rain_vulnerable() -> bool:
	if _is_resource_spawn_pickup():
		return false
	return get_element_id() in [&"wood", &"charcoal", &"iron", &"sulfur", &"lithium", &"sodium", &"energy_cell"]


func _is_resource_spawn_pickup() -> bool:
	if StringName(get_meta(&"pickup_origin", &"")) == &"resource_spawn":
		return true
	return has_meta(&"tile_coords")


func _is_sheltered_from_rain() -> bool:
	return EventBus.get_weather_system() != null \
		and EventBus.get_weather_system().has_method("get_shelter_at") \
		and bool(EventBus.get_weather_system().get_shelter_at(global_position))


func _get_pickup_item_data() -> Dictionary:
	var stored_item_data = get_meta(&"item_data", {})
	if stored_item_data is Dictionary and not stored_item_data.is_empty():
		return stored_item_data.duplicate(true)

	var resolved_element_id := element_id
	if resolved_element_id.is_empty():
		resolved_element_id = get_meta(&"element_id", &"")

	if resolved_element_id.is_empty():
		return {}

	return GameplayData.elements().get_element(resolved_element_id)


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

	# Limestone: none
	var anim_limestone := Animation.new()
	anim_limestone.length = 1.5
	anim_limestone.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle_limestone", anim_limestone)

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

	# Water: subtle bob and shimmer.
	var anim_water := Animation.new()
	anim_water.length = 1.8
	anim_water.loop_mode = Animation.LOOP_LINEAR
	var track_water_position := anim_water.add_track(Animation.TYPE_VALUE)
	anim_water.track_set_path(track_water_position, "Sprite2D:position")
	anim_water.track_insert_key(track_water_position, 0.0, Vector2.ZERO)
	anim_water.track_insert_key(track_water_position, 0.9, Vector2(0.0, -1.0))
	anim_water.track_insert_key(track_water_position, 1.8, Vector2.ZERO)
	var track_water_modulate := anim_water.add_track(Animation.TYPE_VALUE)
	anim_water.track_set_path(track_water_modulate, "Sprite2D:modulate")
	anim_water.track_insert_key(track_water_modulate, 0.0, Color(1.0, 1.0, 1.0, 0.95))
	anim_water.track_insert_key(track_water_modulate, 0.9, Color(0.92, 0.98, 1.0, 1.0))
	anim_water.track_insert_key(track_water_modulate, 1.8, Color(1.0, 1.0, 1.0, 0.95))
	lib.add_animation("idle_water", anim_water)

	# Sulfur: subtle crystal glint.
	var anim_sulfur := Animation.new()
	anim_sulfur.length = 1.2
	anim_sulfur.loop_mode = Animation.LOOP_LINEAR
	var track_sulfur_scale := anim_sulfur.add_track(Animation.TYPE_VALUE)
	anim_sulfur.track_set_path(track_sulfur_scale, "Sprite2D:scale")
	anim_sulfur.track_insert_key(track_sulfur_scale, 0.0, Vector2.ONE)
	anim_sulfur.track_insert_key(track_sulfur_scale, 0.6, Vector2(1.04, 0.98))
	anim_sulfur.track_insert_key(track_sulfur_scale, 1.2, Vector2.ONE)
	lib.add_animation("idle_sulfur", anim_sulfur)

	# Lithium: faint electric shimmer.
	var anim_lithium := Animation.new()
	anim_lithium.length = 2.0
	anim_lithium.loop_mode = Animation.LOOP_LINEAR
	var track_lithium_sprite := anim_lithium.add_track(Animation.TYPE_VALUE)
	anim_lithium.track_set_path(track_lithium_sprite, "Sprite2D:modulate")
	anim_lithium.track_insert_key(track_lithium_sprite, 0.0, Color(0.86, 0.94, 1.0, 0.78))
	anim_lithium.track_insert_key(track_lithium_sprite, 1.0, Color(0.96, 0.99, 1.0, 1.0))
	anim_lithium.track_insert_key(track_lithium_sprite, 2.0, Color(0.86, 0.94, 1.0, 0.78))
	var track_lithium_glow := anim_lithium.add_track(Animation.TYPE_VALUE)
	anim_lithium.track_set_path(track_lithium_glow, "GlowSprite2D:modulate")
	anim_lithium.track_insert_key(track_lithium_glow, 0.0, Color(0.46, 0.82, 1.0, 0.78))
	anim_lithium.track_insert_key(track_lithium_glow, 1.0, Color(0.60, 0.92, 1.0, 1.0))
	anim_lithium.track_insert_key(track_lithium_glow, 2.0, Color(0.46, 0.82, 1.0, 0.78))
	lib.add_animation("idle_lithium", anim_lithium)

	anim_player.add_animation_library("", lib)


func _play_idle_animation() -> void:
	var resolved_element_id := get_element_id()

	var anim_name := "idle_" + str(resolved_element_id)
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)


func get_element_id() -> StringName:
	if not element_id.is_empty():
		return element_id
	return get_meta(&"element_id", &"")


func _apply_visual_identity() -> void:
	var item_data := _get_pickup_item_data()
	var resolved_item_id := StringName(str(item_data.get(&"id", get_element_id())))
	var display_name := str(item_data.get(&"display_name", resolved_item_id))
	var symbol := str(item_data.get(&"symbol", ""))
	var pickup_display_name := display_name

	if pickup_quantity > 1:
		pickup_display_name = "%s x%d" % [pickup_display_name, pickup_quantity]

	prompt_label.text = ""

	sprite.texture = _get_pickup_texture(String(resolved_item_id))
	sprite.modulate = _get_pickup_modulate(item_data, resolved_item_id)
	glow_sprite.texture = null
	glow_sprite.visible = false
	glow_sprite.modulate = Color(1.0, 0.46, 0.18, 0.6)
	sulfur_particles.visible = false
	sulfur_particles.emitting = false

	if resolved_item_id == &"charcoal":
		glow_sprite.texture = _get_glow_texture(String(resolved_item_id))
		glow_sprite.visible = true
	elif resolved_item_id == &"lithium":
		glow_sprite.texture = _get_glow_texture(String(resolved_item_id))
		glow_sprite.visible = true
		glow_sprite.modulate = Color(0.46, 0.82, 1.0, 0.78)
	elif resolved_item_id == &"sulfur":
		_configure_sulfur_particles()
		sulfur_particles.visible = true
		sulfur_particles.emitting = true
	prompt_label.visible = false


func _get_pickup_modulate(item_data: Dictionary, item_id: StringName) -> Color:
	var element_data := GameplayData.elements().get_element(item_id)
	if not element_data.is_empty():
		return Color.WHITE

	var category := _resolve_inventory_category(item_data.get("category", InventoryManager.InventoryItemCategory.GENERIC))
	match category:
		InventoryManager.InventoryItemCategory.TOOL:
			return Color(0.78, 0.67, 0.46, 1.0)
		InventoryManager.InventoryItemCategory.CRAFTED:
			return Color(0.67, 0.80, 0.92, 1.0)
		InventoryManager.InventoryItemCategory.CONSUMABLE:
			return Color(0.88, 0.42, 0.30, 1.0)
		_:
			return Color(0.88, 0.88, 0.88, 1.0)


func _resolve_inventory_category(category_value) -> int:
	if category_value is int:
		return category_value

	match String(category_value).to_lower():
		"element":
			return InventoryManager.InventoryItemCategory.ELEMENT
		"tool":
			return InventoryManager.InventoryItemCategory.TOOL
		"crafted":
			return InventoryManager.InventoryItemCategory.CRAFTED
		"consumable":
			return InventoryManager.InventoryItemCategory.CONSUMABLE
		_:
			return InventoryManager.InventoryItemCategory.GENERIC


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
		"water":
			_build_water_texture(image)
		"charcoal":
			_build_charcoal_texture(image)
		"sulfur":
			_build_sulfur_texture(image)
		"lithium":
			_build_lithium_texture(image)
		"sodium":
			_build_sodium_texture(image)
		"mercury":
			_build_mercury_texture(image)
		"limestone":
			_build_limestone_texture(image)
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
	elif element_key == "lithium":
		var lithium_center := Vector2(8.0, 8.0)
		for y in range(16):
			for x in range(16):
				var lithium_distance := Vector2(float(x), float(y)).distance_to(lithium_center)
				var lithium_alpha := clampf(1.0 - (lithium_distance / 7.0), 0.0, 1.0) * 0.42
				if lithium_alpha > 0.0:
					image.set_pixel(x, y, Color(0.38, 0.80, 1.0, lithium_alpha))

	var texture := ImageTexture.create_from_image(image)
	_glow_textures[element_key] = texture
	return texture


func _build_generic_texture(image: Image) -> void:
	for y in range(4, 12):
		for x in range(4, 12):
			image.set_pixel(x, y, Color(0.88, 0.88, 0.88, 1.0))


func _build_sulfur_texture(image: Image) -> void:
	var core := Color(0.93, 0.86, 0.22, 1.0)
	var highlight := Color(1.0, 0.97, 0.56, 1.0)
	var shadow := Color(0.71, 0.58, 0.09, 1.0)
	var pixels := [
		Vector2i(8, 2), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4),
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5),
		Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6), Vector2i(10, 6),
		Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7),
		Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8),
		Vector2i(8, 9)
	]
	for pixel: Vector2i in pixels:
		image.set_pixel(pixel.x, pixel.y, core)
	for pixel: Vector2i in [Vector2i(7, 3), Vector2i(8, 3), Vector2i(6, 4), Vector2i(7, 4), Vector2i(7, 5)]:
		image.set_pixel(pixel.x, pixel.y, highlight)
	for pixel: Vector2i in [Vector2i(10, 5), Vector2i(9, 6), Vector2i(10, 6), Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9)]:
		image.set_pixel(pixel.x, pixel.y, shadow)


func _build_lithium_texture(image: Image) -> void:
	var core := Color(0.70, 0.84, 0.98, 1.0)
	var highlight := Color(0.92, 0.98, 1.0, 1.0)
	var accent := Color(0.40, 0.76, 1.0, 1.0)
	var shadow := Color(0.34, 0.53, 0.76, 1.0)
	var pixels := [
		Vector2i(8, 1),
		Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 2),
		Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3),
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4),
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5),
		Vector2i(10, 5), Vector2i(11, 5),
		Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6), Vector2i(10, 6),
		Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7),
		Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8),
		Vector2i(8, 9)
	]
	for pixel: Vector2i in pixels:
		image.set_pixel(pixel.x, pixel.y, core)
	for pixel: Vector2i in [Vector2i(8, 1), Vector2i(7, 2), Vector2i(8, 2), Vector2i(7, 3), Vector2i(8, 3), Vector2i(7, 4)]:
		image.set_pixel(pixel.x, pixel.y, highlight)
	for pixel: Vector2i in [Vector2i(10, 3), Vector2i(10, 4), Vector2i(11, 5), Vector2i(9, 7)]:
		image.set_pixel(pixel.x, pixel.y, accent)
	for pixel: Vector2i in [Vector2i(10, 5), Vector2i(10, 6), Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9)]:
		image.set_pixel(pixel.x, pixel.y, shadow)


func _build_sodium_texture(image: Image) -> void:
	var core := Color(0.86, 0.88, 0.78, 1.0)
	var highlight := Color(1.0, 0.98, 0.82, 1.0)
	var shadow := Color(0.60, 0.64, 0.54, 1.0)
	for y in range(4, 12):
		for x in range(4, 12):
			if Vector2(float(x), float(y)).distance_to(Vector2(7.5, 7.5)) <= 4.2:
				image.set_pixel(x, y, core)
	for pixel: Vector2i in [Vector2i(6, 4), Vector2i(7, 4), Vector2i(5, 5), Vector2i(6, 5)]:
		image.set_pixel(pixel.x, pixel.y, highlight)
	for pixel: Vector2i in [Vector2i(10, 8), Vector2i(9, 9), Vector2i(10, 9), Vector2i(8, 10)]:
		image.set_pixel(pixel.x, pixel.y, shadow)


func _build_mercury_texture(image: Image) -> void:
	var core := Color(0.78, 0.81, 0.86, 1.0)
	var highlight := Color(0.96, 0.98, 1.0, 1.0)
	var shadow := Color(0.46, 0.49, 0.55, 1.0)
	var beads := [
		{&"center": Vector2(6.0, 7.0), &"radius": 3.2},
		{&"center": Vector2(10.0, 9.0), &"radius": 2.5},
		{&"center": Vector2(9.0, 5.0), &"radius": 1.8},
	]
	for bead: Dictionary in beads:
		var center := bead[&"center"] as Vector2
		var radius := float(bead[&"radius"])
		for y in range(2, 13):
			for x in range(2, 13):
				if Vector2(float(x), float(y)).distance_to(center) <= radius:
					image.set_pixel(x, y, core)
	for pixel: Vector2i in [Vector2i(5, 5), Vector2i(8, 4), Vector2i(9, 8)]:
		image.set_pixel(pixel.x, pixel.y, highlight)
	for pixel: Vector2i in [Vector2i(7, 9), Vector2i(11, 10), Vector2i(10, 6)]:
		image.set_pixel(pixel.x, pixel.y, shadow)


func _configure_sulfur_particles() -> void:
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 22.0
	process_material.initial_velocity_min = 4.0
	process_material.initial_velocity_max = 9.0
	process_material.gravity = Vector3(0.0, -4.0, 0.0)
	process_material.scale_min = 0.25
	process_material.scale_max = 0.45
	process_material.color = Color(1.0, 0.96, 0.68, 0.8)
	process_material.color_ramp = _build_sulfur_particle_gradient()
	sulfur_particles.process_material = process_material
	sulfur_particles.texture = _build_sulfur_particle_texture()
	sulfur_particles.amount = 5
	sulfur_particles.amount_ratio = 1.0
	sulfur_particles.lifetime = 0.8
	sulfur_particles.one_shot = false
	sulfur_particles.explosiveness = 0.0
	sulfur_particles.position = Vector2(0.0, -2.0)
	sulfur_particles.visibility_rect = Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0))


func _build_sulfur_particle_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.92, 0.0))
	gradient.add_point(0.2, Color(1.0, 0.98, 0.74, 0.85))
	gradient.add_point(1.0, Color(0.95, 0.82, 0.28, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_sulfur_particle_texture() -> Texture2D:
	var image := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(6):
		for x in range(6):
			var distance := Vector2(float(x), float(y)).distance_to(Vector2(2.5, 2.5))
			var alpha := clampf(1.0 - distance / 2.8, 0.0, 1.0)
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _refresh_prompt_state() -> void:
	prompt_label.text = ""
	prompt_label.visible = false


func _can_extract_pickup(item_data: Dictionary) -> bool:
	var resolved_element_id: StringName = item_data.get(&"id", &"")
	if resolved_element_id != &"sulfur":
		return true
	return InventoryManager.has_item(DISTILLATION_KIT_ITEM_ID, 1)


func _apply_extraction_cost(item_data: Dictionary) -> void:
	var resolved_element_id: StringName = item_data.get(&"id", &"")
	if resolved_element_id != &"sulfur":
		return
	InventoryManager.degrade_item(DISTILLATION_KIT_ITEM_ID, DISTILLATION_KIT_DURABILITY_LOSS)


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


func _build_limestone_texture(image: Image) -> void:
	var body := Color(0.85, 0.85, 0.85, 1.0)
	var shadow := Color(0.65, 0.65, 0.65, 1.0)
	for y in range(3, 13):
		for x in range(3, 13):
			if abs(x - 8) + abs(y - 8) <= 6:
				image.set_pixel(x, y, body)
	for pos in [Vector2i(5, 5), Vector2i(8, 6), Vector2i(6, 9), Vector2i(9, 10), Vector2i(4, 8), Vector2i(10, 7)]:
		image.set_pixel(pos.x, pos.y, shadow)


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


func _build_water_texture(image: Image) -> void:
	var deep := Color(0.13, 0.40, 0.67, 1.0)
	var mid := Color(0.22, 0.58, 0.84, 1.0)
	var light := Color(0.58, 0.84, 0.96, 1.0)
	var foam := Color(0.88, 0.98, 1.0, 1.0)

	for y in range(3, 13):
		for x in range(3, 13):
			image.set_pixel(x, y, mid)

	for y in range(4, 12):
		image.set_pixel(3, y, deep)
		image.set_pixel(12, y, deep)

	for x in range(5, 11):
		image.set_pixel(x, 5, light)
		image.set_pixel(x - 1, 9, light)

	for pixel: Vector2i in [Vector2i(5, 4), Vector2i(10, 6), Vector2i(7, 8), Vector2i(9, 10)]:
		image.set_pixel(pixel.x, pixel.y, foam)
