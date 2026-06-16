extends "res://scripts/PlacedObject.gd"

const STANDBY_DRAIN_UNITS_PER_MINUTE := 0.05
const MAX_DURABILITY := 10
const SHOCK_COST := 0.5
const SHOCK_COOLDOWN_SECONDS := 1.5
const SHOCK_DAMAGE := 18
const RAIN_DAMAGE_MULTIPLIER := 1.5
const SHORT_CIRCUIT_CHANCE := 0.15
const SHORT_CIRCUIT_SPLASH_RADIUS_PIXELS := 16.0
const REPAIR_ITEM_ID := &"iron"
const REPAIR_ITEM_COUNT := 1
const DAMAGE_TYPE := &"electrical"

const TRAP_DIM := Color(0.09, 0.12, 0.14, 1.0)
const TRAP_METAL := Color(0.34, 0.40, 0.43, 1.0)
const TRAP_ARMED := Color(0.31, 0.86, 0.95, 1.0)
const TRAP_SHOCK := Color(0.95, 1.0, 0.62, 1.0)
const TRAP_BROKEN := Color(0.20, 0.10, 0.10, 1.0)
const TRAP_BROKEN_METAL := Color(0.18, 0.18, 0.18, 1.0)

@export var durability: int = MAX_DURABILITY

@onready var trigger_area: Area2D = $TriggerArea

var _shock_cooldowns_by_enemy_id: Dictionary = {}
var _flash_timer := 0.0
var _last_armed_visual := false
var _is_broken := false
var _rng := RandomNumberGenerator.new()
var _repair_prompt_label: Label = null
var _player_in_repair_range := false


func _ready() -> void:
	object_type = "electric_trap"
	save_bucket = SaveBucket.STATIONS
	super()
	_rng.randomize()
	add_to_group(&"electric_trap")
	collision_layer = 0
	collision_mask = 0
	_ensure_repair_prompt()
	_sync_broken_state()
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	if BaseDefenseSystem != null and BaseDefenseSystem.has_method("register_power_consumer"):
		BaseDefenseSystem.register_power_consumer(self, STANDBY_DRAIN_UNITS_PER_MINUTE)
	set_process(true)


func _exit_tree() -> void:
	if BaseDefenseSystem != null and BaseDefenseSystem.has_method("unregister_power_consumer"):
		BaseDefenseSystem.unregister_power_consumer(self)


func _process(delta: float) -> void:
	_prune_cooldowns()
	_refresh_repair_interaction()
	if _is_broken:
		_set_armed_visual(false)
		return
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		if _flash_timer <= 0.0:
			_build_trap_texture(_is_armed())
		return
	for body_variant in trigger_area.get_overlapping_bodies():
		var body: Node = body_variant as Node
		_try_shock_body(body)
	_set_armed_visual(_is_armed())


func _on_trigger_body_entered(body: Node) -> void:
	_try_shock_body(body)


func _try_shock_body(body: Node) -> void:
	if body == null or not body.is_in_group(&"enemy"):
		return
	if not _is_armed():
		return
	var enemy_id: int = body.get_instance_id()
	var now_seconds := Time.get_ticks_msec() / 1000.0
	if now_seconds < float(_shock_cooldowns_by_enemy_id.get(enemy_id, 0.0)):
		return
	if BaseGrid == null or not BaseGrid.has_method("consume_charge") or not BaseGrid.consume_charge(SHOCK_COST):
		return

	_shock_cooldowns_by_enemy_id[enemy_id] = now_seconds + SHOCK_COOLDOWN_SECONDS
	_apply_electrical_damage(body)
	_decrement_durability()
	_flash_timer = 0.18
	_build_trap_texture(true, true)
	if _is_raining() and not _is_broken and _rng.randf() < SHORT_CIRCUIT_CHANCE:
		_trigger_short_circuit()


func _is_armed() -> bool:
	if _is_broken:
		return false
	if PowerSwitchboard != null and PowerSwitchboard.has_method("is_consumer_enabled"):
		if not PowerSwitchboard.is_consumer_enabled(PowerSwitchboard.CONSUMER_TRAP_NETWORK):
			return false
	return BaseGrid != null and BaseGrid.has_method("get_charge_state") and float(BaseGrid.get_charge_state()) >= SHOCK_COST


func get_power_drain_units_per_minute() -> float:
	if _is_broken:
		return 0.0
	if PowerSwitchboard != null and PowerSwitchboard.has_method("is_consumer_enabled"):
		if not PowerSwitchboard.is_consumer_enabled(PowerSwitchboard.CONSUMER_TRAP_NETWORK):
			return 0.0
	return STANDBY_DRAIN_UNITS_PER_MINUTE


func get_occupied_tile_coords() -> Array[Vector2i]:
	var offsets := _get_occupied_offsets()
	var coords: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		coords.append(placed_at + offset)
	return coords


func to_world_save_entry() -> Dictionary:
	var entry := super.to_world_save_entry()
	entry[&"durability"] = durability
	entry[&"is_broken"] = _is_broken
	return entry


func restore_from_pickup(data: Dictionary) -> void:
	durability = clampi(int(data.get(&"durability", durability)), 0, MAX_DURABILITY)
	_is_broken = bool(data.get(&"is_broken", durability <= 0))
	_sync_broken_state()


func repair_to_full() -> bool:
	if durability >= MAX_DURABILITY and not _is_broken:
		return false
	durability = MAX_DURABILITY
	_is_broken = false
	_sync_broken_state()
	GameManager.mark_dirty()
	return true


func _apply_electrical_damage(body: Node) -> void:
	var base_damage := float(SHOCK_DAMAGE)
	if _is_raining():
		base_damage *= RAIN_DAMAGE_MULTIPLIER
	_apply_resolved_electrical_damage(body, base_damage, "Electric trap")


func _apply_resolved_electrical_damage(body: Node, base_damage: float, source_label: String) -> void:
	var resolved_damage := int(DamageCalculator.calculate(base_damage, DAMAGE_TYPE, body, global_position))
	var health_system: Node = body.get_node_or_null("HealthSystem")
	if health_system == null:
		health_system = body.find_child("HealthSystem", true, false)
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(resolved_damage, DAMAGE_TYPE, source_label)
	elif body.has_method("take_resolved_damage"):
		body.take_resolved_damage(resolved_damage, DAMAGE_TYPE, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(resolved_damage, DAMAGE_TYPE, global_position)
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(resolved_damage, DAMAGE_TYPE, source_label)


func _decrement_durability() -> void:
	if _is_broken:
		return
	durability = maxi(durability - 1, 0)
	if durability <= 0:
		_break_trap()
	GameManager.mark_dirty()


func _trigger_short_circuit() -> void:
	_apply_short_circuit_splash()
	_break_trap()
	GameManager.mark_dirty()


func _apply_short_circuit_splash() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SHORT_CIRCUIT_SPLASH_RADIUS_PIXELS
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1

	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body := hit.get("collider") as Node
		if body == null or body == self:
			continue
		if not body.is_in_group(&"enemy") and not body.is_in_group(&"player"):
			continue
		_apply_resolved_electrical_damage(body, float(SHOCK_DAMAGE), "Trap short-circuit")


func _break_trap() -> void:
	durability = 0
	_is_broken = true
	_flash_timer = 0.0
	_shock_cooldowns_by_enemy_id.clear()
	_sync_broken_state()


func _sync_broken_state() -> void:
	_is_broken = _is_broken or durability <= 0
	_build_trap_texture(false)
	_refresh_repair_prompt()


func _prune_cooldowns() -> void:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	var stale_ids: Array[int] = []
	for enemy_id_variant in _shock_cooldowns_by_enemy_id.keys():
		var enemy_id := int(enemy_id_variant)
		if now_seconds >= float(_shock_cooldowns_by_enemy_id[enemy_id]):
			stale_ids.append(enemy_id)
	for enemy_id in stale_ids:
		_shock_cooldowns_by_enemy_id.erase(enemy_id)


func _build_trap_texture(is_armed: bool, is_shocking: bool = false) -> void:
	if sprite == null:
		return

	var image := Image.create(56, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rail_color := TRAP_SHOCK if is_shocking else (TRAP_ARMED if is_armed else TRAP_METAL)
	if _is_broken:
		rail_color = TRAP_BROKEN_METAL

	for y in range(6, 14):
		for x in range(4, 52):
			image.set_pixel(x, y, TRAP_BROKEN if _is_broken else TRAP_DIM)
	for x in range(5, 51):
		image.set_pixel(x, 5, rail_color)
		image.set_pixel(x, 14, rail_color)
	for x in range(8, 49, 8):
		for y in range(4, 16):
			image.set_pixel(x, y, rail_color)
			image.set_pixel(x + 1, y, rail_color)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2.ZERO
	_last_armed_visual = is_armed


func _set_armed_visual(is_armed: bool) -> void:
	if is_armed == _last_armed_visual:
		return
	_build_trap_texture(is_armed)


func _refresh_repair_interaction() -> void:
	_player_in_repair_range = _find_player_in_trigger_area() != null
	_refresh_repair_prompt()
	if not _player_in_repair_range:
		return
	if durability >= MAX_DURABILITY and not _is_broken:
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not InventoryManager.has_item(REPAIR_ITEM_ID, REPAIR_ITEM_COUNT):
		return
	if not InventoryManager.remove_item(REPAIR_ITEM_ID, REPAIR_ITEM_COUNT):
		return
	repair_to_full()


func _find_player_in_trigger_area() -> Node:
	if trigger_area == null:
		return null
	for body_variant in trigger_area.get_overlapping_bodies():
		var body := body_variant as Node
		if body != null and body.is_in_group(&"player"):
			return body
	return null


func _ensure_repair_prompt() -> void:
	if _repair_prompt_label != null:
		return
	_repair_prompt_label = Label.new()
	_repair_prompt_label.name = "RepairPromptLabel"
	_repair_prompt_label.visible = false
	_repair_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_repair_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_repair_prompt_label.add_theme_font_size_override("font_size", 8)
	_repair_prompt_label.add_theme_constant_override("outline_size", 1)
	_repair_prompt_label.offset_left = -84.0
	_repair_prompt_label.offset_top = -34.0
	_repair_prompt_label.offset_right = 84.0
	_repair_prompt_label.offset_bottom = -4.0
	add_child(_repair_prompt_label)


func _refresh_repair_prompt() -> void:
	if _repair_prompt_label == null:
		return
	var needs_repair := _is_broken or durability < MAX_DURABILITY
	_repair_prompt_label.visible = _player_in_repair_range and needs_repair
	if not _repair_prompt_label.visible:
		return
	if InventoryManager.has_item(REPAIR_ITEM_ID, REPAIR_ITEM_COUNT):
		_repair_prompt_label.text = "[E] Repair Trap (Iron x1) %d/%d" % [durability, MAX_DURABILITY]
	else:
		_repair_prompt_label.text = "Needs Iron x1 to repair %d/%d" % [durability, MAX_DURABILITY]


func _is_raining() -> bool:
	return WeatherSystem != null \
		and WeatherSystem.has_method("get_current_state") \
		and int(WeatherSystem.get_current_state()) == WeatherSystem.WeatherState.RAIN


func _get_occupied_offsets() -> Array[Vector2i]:
	var normalized_rotation := posmod(int(round(rotation_degrees)), 180)
	if normalized_rotation == 90:
		return [Vector2i(0, -1), Vector2i.ZERO, Vector2i(0, 1)]
	return [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
