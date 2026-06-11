extends "res://scripts/PlacedObject.gd"

const STANDBY_DRAIN_UNITS_PER_MINUTE := 0.05
const SHOCK_COST := 0.5
const SHOCK_COOLDOWN_SECONDS := 1.5
const SHOCK_DAMAGE := 18
const DAMAGE_TYPE := &"electrical"

const TRAP_DIM := Color(0.09, 0.12, 0.14, 1.0)
const TRAP_METAL := Color(0.34, 0.40, 0.43, 1.0)
const TRAP_ARMED := Color(0.31, 0.86, 0.95, 1.0)
const TRAP_SHOCK := Color(0.95, 1.0, 0.62, 1.0)

@onready var trigger_area: Area2D = $TriggerArea

var _shock_cooldowns_by_enemy_id: Dictionary = {}
var _flash_timer := 0.0
var _last_armed_visual := false


func _ready() -> void:
	object_type = "electric_trap"
	save_bucket = SaveBucket.STATIONS
	super()
	collision_layer = 0
	collision_mask = 0
	_build_trap_texture(false)
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	if BaseDefenseSystem != null and BaseDefenseSystem.has_method("register_power_consumer"):
		BaseDefenseSystem.register_power_consumer(self, STANDBY_DRAIN_UNITS_PER_MINUTE)
	set_process(true)


func _exit_tree() -> void:
	if BaseDefenseSystem != null and BaseDefenseSystem.has_method("unregister_power_consumer"):
		BaseDefenseSystem.unregister_power_consumer(self)


func _process(delta: float) -> void:
	_prune_cooldowns()
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
	_flash_timer = 0.18
	_build_trap_texture(true, true)


func _is_armed() -> bool:
	return BaseGrid != null and BaseGrid.has_method("get_charge_state") and float(BaseGrid.get_charge_state()) >= SHOCK_COST


func get_occupied_tile_coords() -> Array[Vector2i]:
	var offsets := _get_occupied_offsets()
	var coords: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		coords.append(placed_at + offset)
	return coords


func _apply_electrical_damage(body: Node) -> void:
	var resolved_damage := int(DamageCalculator.calculate(float(SHOCK_DAMAGE), DAMAGE_TYPE, body, global_position))
	var health_system: Node = body.get_node_or_null("HealthSystem")
	if health_system == null:
		health_system = body.find_child("HealthSystem", true, false)
	if health_system != null and health_system.has_method("take_resolved_damage"):
		health_system.take_resolved_damage(resolved_damage, DAMAGE_TYPE, "Electric trap")
	elif body.has_method("take_resolved_damage"):
		body.take_resolved_damage(resolved_damage, DAMAGE_TYPE, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(resolved_damage, DAMAGE_TYPE, global_position)
	elif health_system != null and health_system.has_method("take_damage"):
		health_system.take_damage(resolved_damage, DAMAGE_TYPE, "Electric trap")


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

	for y in range(6, 14):
		for x in range(4, 52):
			image.set_pixel(x, y, TRAP_DIM)
	for x in range(5, 51):
		image.set_pixel(x, 5, rail_color)
		image.set_pixel(x, 14, rail_color)
	for x in range(8, 49, 8):
		for y in range(4, 16):
			image.set_pixel(x, y, rail_color)
			image.set_pixel(x + 1, y, rail_color)
	if is_shocking:
		for x in range(10, 46, 12):
			image.set_pixel(x, 3, TRAP_SHOCK)
			image.set_pixel(x + 2, 6, TRAP_SHOCK)
			image.set_pixel(x + 4, 3, TRAP_SHOCK)

	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = Vector2.ZERO
	_last_armed_visual = is_armed


func _set_armed_visual(is_armed: bool) -> void:
	if is_armed == _last_armed_visual:
		return
	_build_trap_texture(is_armed)


func _get_occupied_offsets() -> Array[Vector2i]:
	var normalized_rotation := posmod(int(round(rotation_degrees)), 180)
	if normalized_rotation == 90:
		return [Vector2i(0, -1), Vector2i.ZERO, Vector2i(0, 1)]
	return [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
