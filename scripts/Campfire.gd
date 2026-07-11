extends "res://scripts/PlacedObject.gd"

const BURN_DURATION_SECONDS := 600.0
const CHARCOAL_CYCLE_SECONDS := 120.0
const CHARCOAL_STATUS_SHOW_SECONDS := 1.6
const CHARCOAL_ITEM_ID := &"charcoal"
const REFUEL_COST_ITEM_ID := &"wood"
const REFUEL_COST_QUANTITY := 2
const RELIGHT_COST_QUANTITY := 2
const HEAL_PER_SECOND := 1.5
const SUPPORT_RADIUS := 42.0
const SHELTERED_SUPPORT_RADIUS := 58.0
const LIGHT_ENERGY_LIT := 0.7
const LIGHT_ENERGY_UNLIT := 0.0
const LIGHT_ENERGY_RAIN_EXPOSED := 0.24
const RAIN_EXPOSED_BURN_MULTIPLIER := 8.0
const LIGHT_TEXTURE_SCALE := 0.44
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
var _extinguish_locked_until_release := false
var _pickup_locked_until_release := false
var _heal_accumulator := 0.0
var _refuel_wood_units_loaded := 0
var _charcoal_progress_seconds := 0.0
var _pending_output_charcoal := 0
var _charcoal_status_text := ""
var _charcoal_status_seconds := 0.0
var _is_sheltered := false
var _was_rain_exposed := false


func _ready() -> void:
	object_type = "campfire"
	save_bucket = SaveBucket.STATIONS
	super()
	_build_visual_identity()
	_configure_support_area()
	_configure_light()
	_configure_particles()
	_configure_prompt_label()
	support_area.body_entered.connect(_on_body_entered)
	support_area.body_exited.connect(_on_body_exited)
	_apply_lit_state()
	_hide_prompt()


func _process(delta: float) -> void:
	_sync_player_range_state()
	_update_shelter_state()
	_update_burn(delta)
	_update_charcoal_processing(delta)
	_update_charcoal_status(delta)
	_update_interaction_lock()
	_handle_refuel_input()
	_handle_relight_input()
	_handle_extinguish_input()
	_handle_charcoal_collect_input()
	_handle_pickup_input()
	_handle_healing(delta)
	_update_warmth_state()
	_update_rain_fire_visual_state()


func to_world_save_entry() -> Dictionary:
	var entry := super.to_world_save_entry()
	entry[&"is_lit"] = is_lit
	entry[&"burn_time_remaining"] = burn_time_remaining
	entry[&"refuel_wood_units_loaded"] = _refuel_wood_units_loaded
	entry[&"charcoal_progress_seconds"] = _charcoal_progress_seconds
	entry[&"pending_output_charcoal"] = _pending_output_charcoal
	return entry


func restore_from_pickup(data: Dictionary) -> void:
	if data.has(&"burn_time_remaining"):
		burn_time_remaining = maxf(0.0, float(data[&"burn_time_remaining"]))
	_refuel_wood_units_loaded = int(data.get(&"refuel_wood_units_loaded", 0))
	_charcoal_progress_seconds = clampf(float(data.get(&"charcoal_progress_seconds", 0.0)), 0.0, CHARCOAL_CYCLE_SECONDS)
	_pending_output_charcoal = maxi(int(data.get(&"pending_output_charcoal", 0)), 0)
	if data.has(&"is_lit"):
		is_lit = bool(data[&"is_lit"])
	else:
		is_lit = burn_time_remaining > 0.0
	if burn_time_remaining <= 0.0:
		is_lit = false
	_apply_lit_state()


func _update_burn(delta: float) -> void:
	if not is_lit:
		return
	var burn_multiplier := RAIN_EXPOSED_BURN_MULTIPLIER if _is_rain_exposed() else 1.0
	burn_time_remaining = maxf(0.0, burn_time_remaining - delta * burn_multiplier)
	if burn_time_remaining <= 0.0:
		is_lit = false
		_apply_lit_state()
		if _was_rain_exposed:
			_set_charcoal_status("Rain put the campfire out")


func _update_charcoal_processing(delta: float) -> void:
	if not is_lit or _refuel_wood_units_loaded <= 0:
		return

	_charcoal_progress_seconds += delta
	var produced_charcoal := 0
	while _charcoal_progress_seconds >= CHARCOAL_CYCLE_SECONDS and _refuel_wood_units_loaded > 0:
		_charcoal_progress_seconds -= CHARCOAL_CYCLE_SECONDS
		_refuel_wood_units_loaded -= 1
		_pending_output_charcoal += 1
		produced_charcoal += 1
	if _refuel_wood_units_loaded <= 0:
		_charcoal_progress_seconds = 0.0

	if produced_charcoal > 0:
		GameManager.mark_dirty()
		_set_charcoal_status("Charcoal ready x%d" % _pending_output_charcoal)


func _update_interaction_lock() -> void:
	if _interact_locked_until_release and not Input.is_action_pressed("interact"):
		_interact_locked_until_release = false
	if _extinguish_locked_until_release and not Input.is_key_pressed(KEY_F):
		_extinguish_locked_until_release = false
	if _pickup_locked_until_release and not Input.is_key_pressed(KEY_G):
		_pickup_locked_until_release = false


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
	_refuel_wood_units_loaded += REFUEL_COST_QUANTITY
	_interact_locked_until_release = true
	GameManager.mark_dirty()
	_show_prompt(true)


func _handle_relight_input() -> void:
	# Re-light a dead campfire with 2 wood
	if not _player_in_range or is_lit or _interact_locked_until_release:
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not InventoryManager.has_item(REFUEL_COST_ITEM_ID, RELIGHT_COST_QUANTITY):
		return
	if not InventoryManager.remove_item(REFUEL_COST_ITEM_ID, RELIGHT_COST_QUANTITY):
		return
	burn_time_remaining = BURN_DURATION_SECONDS
	_refuel_wood_units_loaded += RELIGHT_COST_QUANTITY
	is_lit = true
	_apply_lit_state()
	_interact_locked_until_release = true
	GameManager.mark_dirty()
	_show_prompt(true)


func _handle_extinguish_input() -> void:
	# Manually extinguish the campfire with F — preserves burn_time_remaining
	if not _player_in_range or not is_lit or _extinguish_locked_until_release:
		return
	if not Input.is_key_pressed(KEY_F):
		return
	is_lit = false
	_apply_lit_state()
	_extinguish_locked_until_release = true
	GameManager.mark_dirty()
	_show_prompt(true)


func _handle_charcoal_collect_input() -> void:
	if not _player_in_range or not Input.is_action_just_pressed("campfire_process"):
		return
	if _pending_output_charcoal <= 0:
		_set_charcoal_status(_build_charcoal_status_text())
		return

	var charcoal_data := ElementDatabase.get_element(CHARCOAL_ITEM_ID)
	if charcoal_data.is_empty():
		return
	if not InventoryManager.can_add_item(charcoal_data, _pending_output_charcoal):
		_set_charcoal_status("Inventory full")
		return
	var collected_charcoal := _pending_output_charcoal
	if not InventoryManager.add_item(charcoal_data, _pending_output_charcoal):
		_set_charcoal_status("Inventory full")
		return

	_pending_output_charcoal = 0
	GameManager.mark_dirty()
	_set_charcoal_status("Collected Charcoal x%d" % collected_charcoal)


func _handle_pickup_input() -> void:
	# Pick up the campfire with G; player can re-place it anywhere for free
	if not _player_in_range or _pickup_locked_until_release:
		return
	if not Input.is_key_pressed(KEY_G):
		return
	CarrierRiskSystem.set_sheltered(get_instance_id(), false)
	if GameManager != null and GameManager.has_method("set_player_warmed"):
		GameManager.set_player_warmed(false)
	var build_system := get_node_or_null("/root/BuildSystem")
	if build_system != null and build_system.has_method("enter_build_mode_for_existing"):
		build_system.call("enter_build_mode_for_existing", scene_file_path, _build_restore_payload())
	queue_free()


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
	var weather_system := _get_rain_system()
	if weather_system != null and weather_system.has_method("get_shelter_at"):
		sheltered = bool(weather_system.call("get_shelter_at", global_position))
	_set_shelter_bonus(sheltered)
	CarrierRiskSystem.set_sheltered(get_instance_id(), sheltered and is_lit and _player_in_range)

func _update_warmth_state() -> void:
	if GameManager != null and GameManager.has_method("set_player_warmed"):
		var should_be_warm = (is_lit and _player_in_range)
		# Only modify if we are currently providing warmth or if we were the one providing it
		if should_be_warm:
			GameManager.set_player_warmed(true)
		elif not is_lit or not _player_in_range:
			# If the player is not in range, we should remove the warmth, but wait, if there are multiple campfires, this might conflict.
			# Let's just set it to false if they leave this specific one, unless we have a better system.
			# For simplicity:
			pass
		# Actually, a better way is for GameManager to check all campfires, or for the player to track warmth sources.
		# But since this is a simple game, we can just let Campfire set it to true when in range, and false when exiting.


func _apply_lit_state() -> void:
	if point_light != null:
		point_light.energy = _get_current_light_energy()
	if flame_particles != null:
		flame_particles.emitting = is_lit
	if sprite != null:
		sprite.modulate = _get_current_sprite_modulate()
	_show_prompt(_player_in_range)


func _update_rain_fire_visual_state() -> void:
	var rain_exposed := _is_rain_exposed()
	if _was_rain_exposed == rain_exposed:
		return
	_was_rain_exposed = rain_exposed
	if rain_exposed and is_lit:
		_set_charcoal_status("Rain is choking the flame")
	if point_light != null:
		point_light.energy = _get_current_light_energy()
	if flame_particles != null:
		flame_particles.amount_ratio = 0.35 if rain_exposed else 1.0
	if sprite != null:
		sprite.modulate = _get_current_sprite_modulate()


func _get_current_light_energy() -> float:
	if not is_lit:
		return LIGHT_ENERGY_UNLIT
	return LIGHT_ENERGY_RAIN_EXPOSED if _is_rain_exposed() else LIGHT_ENERGY_LIT


func _get_current_sprite_modulate() -> Color:
	if not is_lit:
		return Color(0.68, 0.62, 0.56, 1.0)
	return Color(0.72, 0.78, 0.84, 1.0) if _is_rain_exposed() else Color.WHITE


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
	var texture_size := 128
	if MobilePerformance != null and MobilePerformance.has_method("get_light_texture_size"):
		texture_size = int(MobilePerformance.get_light_texture_size())
	texture.width = texture_size
	texture.height = texture_size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient
	point_light.texture = texture
	point_light.texture_scale = LIGHT_TEXTURE_SCALE
	var energy_scale := 1.0
	if MobilePerformance != null and MobilePerformance.has_method("get_light_energy_scale"):
		energy_scale = float(MobilePerformance.get_light_energy_scale())
	point_light.energy = LIGHT_ENERGY_LIT * energy_scale if is_lit else LIGHT_ENERGY_UNLIT
	point_light.offset = Vector2(0.0, -8.0)


func _configure_support_area() -> void:
	if support_shape == null:
		return
	var circle_shape := support_shape.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = SUPPORT_RADIUS


func _set_shelter_bonus(sheltered: bool) -> void:
	if _is_sheltered == sheltered:
		return
	_is_sheltered = sheltered
	if support_shape == null:
		return
	var circle_shape := support_shape.shape as CircleShape2D
	if circle_shape == null:
		return
	circle_shape.radius = SHELTERED_SUPPORT_RADIUS if sheltered else SUPPORT_RADIUS


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
	var particle_scale := 1.0
	if MobilePerformance != null and MobilePerformance.has_method("get_particle_amount_scale"):
		particle_scale = float(MobilePerformance.get_particle_amount_scale())
	flame_particles.amount = maxi(8, int(round(20.0 * particle_scale)))
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
	prompt_label.add_theme_font_size_override("font_size", 8)
	prompt_label.add_theme_constant_override("outline_size", 1)
	prompt_label.offset_left = -84.0
	prompt_label.offset_top = -52.0
	prompt_label.offset_right = 84.0
	prompt_label.offset_bottom = -10.0


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player") and body is CharacterBody2D:
		_set_player_in_range(body as CharacterBody2D)


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_clear_player_in_range()


func _show_prompt(should_show: bool) -> void:
	if prompt_label == null:
		return
	prompt_label.visible = should_show
	if not should_show:
		return
	if is_lit:
		var has_wood := InventoryManager.has_item(REFUEL_COST_ITEM_ID, REFUEL_COST_QUANTITY)
		var refuel_line := (
			"Tap Interact to refuel (%s)" % ("Wood x2" if has_wood else "Need Wood x2")
			if MobileInputRouter.prefers_touch_controls() else
			"[E] Refuel (%s)" % ("Wood x2" if has_wood else "Need Wood x2")
		)
		prompt_label.text = refuel_line if MobileInputRouter.prefers_touch_controls() else "%s\n[F] Extinguish\n[G] Pick up" % refuel_line
	else:
		var has_wood := InventoryManager.has_item(REFUEL_COST_ITEM_ID, RELIGHT_COST_QUANTITY)
		var relight_line := (
			"Tap Interact to relight" if has_wood else "Tap Interact to relight (Need Wood x2)"
			if MobileInputRouter.prefers_touch_controls() else
			("[E] Relight" if has_wood else "[E] Relight (Need Wood x2)")
		)
		prompt_label.text = "Campfire Out\n%s" % relight_line if MobileInputRouter.prefers_touch_controls() else "Campfire Out\n%s\n[G] Pick up" % relight_line
	if _charcoal_status_seconds > 0.0 and not _charcoal_status_text.is_empty():
		prompt_label.text = "%s\n%s" % [prompt_label.text, _charcoal_status_text]


func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.visible = false


func _build_charcoal_status_text() -> String:
	if _pending_output_charcoal > 0:
		return "Collect Charcoal x%d" % _pending_output_charcoal
	if _refuel_wood_units_loaded <= 0:
		return "No charcoal in progress"
	var remaining_seconds := maxi(int(ceil(CHARCOAL_CYCLE_SECONDS - _charcoal_progress_seconds)), 1)
	return "Charcoal in %s" % _format_seconds_short(remaining_seconds)


func _update_charcoal_status(delta: float) -> void:
	if _charcoal_status_seconds <= 0.0:
		return
	_charcoal_status_seconds = maxf(0.0, _charcoal_status_seconds - delta)
	if _charcoal_status_seconds <= 0.0:
		_charcoal_status_text = ""
	if _player_in_range:
		_show_prompt(true)


func _set_charcoal_status(text: String) -> void:
	_charcoal_status_text = text
	_charcoal_status_seconds = CHARCOAL_STATUS_SHOW_SECONDS
	_show_prompt(_player_in_range)


func _format_seconds_short(total_seconds: int) -> String:
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	return "%d:%02d" % [minutes, seconds]


func _build_restore_payload() -> Dictionary:
	return {
		&"burn_time_remaining": burn_time_remaining,
		&"refuel_wood_units_loaded": _refuel_wood_units_loaded,
		&"charcoal_progress_seconds": _charcoal_progress_seconds,
		&"pending_output_charcoal": _pending_output_charcoal,
	}


func _get_rain_system() -> Node:
	var weather_system := get_node_or_null("/root/WeatherSystem")
	if weather_system != null:
		return weather_system
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.find_child("IronHillsZone", true, false)


func _is_rain_exposed() -> bool:
	return is_lit \
		and WeatherSystem != null \
		and WeatherSystem.has_method("get_current_state") \
		and int(WeatherSystem.get_current_state()) == WeatherSystem.WeatherState.RAIN \
		and not _is_sheltered


func _sync_player_range_state() -> void:
	if support_area == null:
		return
	for body in support_area.get_overlapping_bodies():
		if body.is_in_group(&"player") and body is CharacterBody2D:
			_set_player_in_range(body as CharacterBody2D)
			return
	_clear_player_in_range()


func _set_player_in_range(player_body: CharacterBody2D) -> void:
	if player_body == null:
		return
	_player = player_body
	_player_in_range = true
	_show_prompt(true)


func _clear_player_in_range() -> void:
	if not _player_in_range and _player == null:
		return
	_player = null
	_player_in_range = false
	_heal_accumulator = 0.0
	CarrierRiskSystem.set_sheltered(get_instance_id(), false)
	if GameManager != null and GameManager.has_method("set_player_warmed"):
		GameManager.set_player_warmed(false)
	_hide_prompt()
