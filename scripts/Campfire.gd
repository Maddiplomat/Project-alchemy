extends "res://scripts/PlacedObject.gd"

const BURN_DURATION_SECONDS := 600.0
const REFUEL_COST_ITEM_ID := &"wood"
const REFUEL_COST_QUANTITY := 2
const HEAL_PER_SECOND := 1.5
const SUPPORT_RADIUS := 48.0
const LIGHT_ENERGY_LIT := 0.7
const LIGHT_ENERGY_UNLIT := 0.0
const CAMPFIRE_WOOD := Color(0.36, 0.22, 0.10, 1.0)
const CAMPFIRE_WOOD_DARK := Color(0.22, 0.14, 0.07, 1.0)
const CAMPFIRE_STONE := Color(0.48, 0.46, 0.44, 1.0)
const CAMPFIRE_EMBER := Color(1.0, 0.56, 0.14, 1.0)
const CAMPFIRE_FLAME := Color(1.0, 0.76, 0.20, 0.95)

@export var is_lit := true
@export var burn_time_remaining := BURN_DURATION_SECONDS

@onready var point_light: PointLight2D = $PointLight2D
@onready var support_area: Area2D = $SupportArea
@onready var support_shape: CollisionShape2D = $SupportArea/CollisionShape2D
@onready var prompt_label: Label = $PromptLabel
@onready var flame_particles: GPUParticles2D = $FlameParticles

var _player_in_range := false
var _player: CharacterBody2D = null
var _interact_locked_until_release := false
var _heal_accumulator := 0.0


func _ready() -> void:
	object_type = "campfire"
	save_bucket = SaveBucket.STATIONS
	super()
	_build_visual_identity()
	_configure_light()
	_configure_particles()
	_configure_prompt_label()
	support_area.body_entered.connect(_on_body_entered)
	support_area.body_exited.connect(_on_body_exited)
	_apply_lit_state()
	_hide_prompt()


func _process(delta: float) -> void:
	_update_burn(delta)
	_update_interaction_lock()
	_handle_refuel_input()
	_handle_healing(delta)
	_update_shelter_state()


func to_world_save_entry() -> Dictionary:
	var entry := super.to_world_save_entry()
	entry[&"is_lit"] = is_lit
	entry[&"burn_time_remaining"] = burn_time_remaining
	return entry


func _update_burn(delta: float) -> void:
	if not is_lit:
		return
	burn_time_remaining = maxf(0.0, burn_time_remaining - delta)
	if burn_time_remaining <= 0.0:
		is_lit = false
		_apply_lit_state()


func _update_interaction_lock() -> void:
	if _interact_locked_until_release and not Input.is_action_pressed("interact"):
		_interact_locked_until_release = false


func _handle_refuel_input() -> void:
	if not _player_in_range or not is_lit or _interact_locked_until_release:
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not InventoryManager.has_item(REFUEL_COST_ITEM_ID, REFUEL_COST_QUANTITY):
		return
	if not InventoryManager.remove_item(REFUEL_COST_ITEM_ID, REFUEL_COST_QUANTITY):
		return
	burn_time_remaining += BURN_DURATION_SECONDS
	_interact_locked_until_release = true
	GameManager.mark_dirty()
	_show_prompt(true)


func _handle_healing(delta: float) -> void:
	if not is_lit or not _player_in_range or _player == null:
		_heal_accumulator = 0.0
		return
	var health_system := _player.get_node_or_null("HealthSystem")
	if health_system == null or not health_system.has_method("heal"):
		return
	_heal_accumulator += HEAL_PER_SECOND * delta
	while _heal_accumulator >= 1.0:
		health_system.heal(1)
		_heal_accumulator -= 1.0


func _update_shelter_state() -> void:
	if not has_node("/root/CarrierRiskSystem"):
		return
	var sheltered := false
	if is_lit and _player_in_range:
		var rain_system := _get_rain_system()
		if rain_system != null and rain_system.has_method("is_raining"):
			sheltered = bool(rain_system.call("is_raining"))
	CarrierRiskSystem.set_sheltered(get_instance_id(), sheltered)


func _apply_lit_state() -> void:
	if point_light != null:
		point_light.energy = LIGHT_ENERGY_LIT if is_lit else LIGHT_ENERGY_UNLIT
	if flame_particles != null:
		flame_particles.emitting = is_lit
	if sprite != null:
		sprite.modulate = Color.WHITE if is_lit else Color(0.68, 0.62, 0.56, 1.0)
	_show_prompt(_player_in_range)


func _build_visual_identity() -> void:
	if sprite == null:
		return

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(18, 28):
		for x in range(6, 26):
			if y >= 24 and x >= 10 and x <= 22:
				image.set_pixel(x, y, CAMPFIRE_STONE)

	for y in range(16, 24):
		for x in range(10, 14):
			image.set_pixel(x, y, CAMPFIRE_WOOD if (x + y) % 2 == 0 else CAMPFIRE_WOOD_DARK)
		for x in range(18, 22):
			image.set_pixel(x, y, CAMPFIRE_WOOD if (x + y) % 2 == 0 else CAMPFIRE_WOOD_DARK)

	for y in range(12, 22):
		for x in range(14, 18):
			image.set_pixel(x, y, CAMPFIRE_EMBER)

	for y in range(8, 18):
		for x in range(12, 20):
			if abs(x - 15) + y <= 28:
				image.set_pixel(x, y, CAMPFIRE_FLAME)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2(0.0, -4.0)


func _configure_light() -> void:
	if point_light == null:
		return
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.88, 0.52, 0.95))
	gradient.add_point(0.35, Color(1.0, 0.54, 0.18, 0.55))
	gradient.add_point(1.0, Color(0.0, 0.0, 0.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.gradient = gradient
	point_light.texture = texture
	point_light.energy = LIGHT_ENERGY_LIT if is_lit else LIGHT_ENERGY_UNLIT
	point_light.offset = Vector2(0.0, -8.0)


func _configure_particles() -> void:
	if flame_particles == null:
		return
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 22.0
	process_material.initial_velocity_min = 18.0
	process_material.initial_velocity_max = 42.0
	process_material.gravity = Vector3(0.0, -12.0, 0.0)
	process_material.scale_min = 0.7
	process_material.scale_max = 1.4
	process_material.color = Color(1.0, 0.66, 0.18, 1.0)
	process_material.color_ramp = _build_particle_gradient()
	flame_particles.process_material = process_material
	flame_particles.texture = _build_particle_texture()
	flame_particles.amount = 20
	flame_particles.lifetime = 0.8
	flame_particles.emitting = is_lit
	flame_particles.position = Vector2(0.0, -10.0)
	flame_particles.one_shot = false


func _build_particle_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.98, 0.74, 0.0))
	gradient.add_point(0.18, Color(1.0, 0.72, 0.20, 0.95))
	gradient.add_point(0.72, Color(0.96, 0.24, 0.06, 0.62))
	gradient.add_point(1.0, Color(0.18, 0.06, 0.02, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_particle_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(8):
		for x in range(8):
			var distance := Vector2(float(x), float(y)).distance_to(Vector2(3.5, 3.5))
			var alpha := clampf(1.0 - distance / 3.8, 0.0, 1.0)
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _configure_prompt_label() -> void:
	if prompt_label == null:
		return
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.offset_left = -84.0
	prompt_label.offset_top = -52.0
	prompt_label.offset_right = 84.0
	prompt_label.offset_bottom = -10.0


func _on_body_entered(body: Node) -> void:
	if body.name == "Player" and body is CharacterBody2D:
		_player = body as CharacterBody2D
		_player_in_range = true
		_show_prompt(true)


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
	_player_in_range = false
	_heal_accumulator = 0.0
	CarrierRiskSystem.set_sheltered(get_instance_id(), false)
	_hide_prompt()


func _show_prompt(should_show: bool) -> void:
	if prompt_label == null:
		return
	prompt_label.visible = should_show
	if not should_show:
		return
	if is_lit:
		var wood_status := "Ready" if InventoryManager.has_item(REFUEL_COST_ITEM_ID, REFUEL_COST_QUANTITY) else "Need Wood x2"
		prompt_label.text = "Press E to refuel\n%s" % wood_status
	else:
		prompt_label.text = "Campfire Out"


func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.visible = false


func _get_rain_system() -> Node:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.find_child("IronHillsZone", true, false)
