extends StaticBody2D

const FURNACE_UI_SCENE := preload("res://scenes/UI/FurnaceUI.tscn")
const DEFAULT_FUEL_BURN_DURATION := 30.0
const PASSIVE_COOL_RATE := 15.0
const CHARCOAL_ITEM_ID := &"charcoal"
const POWER_CELL_DURATION_SECONDS := 480.0
const UNPOWERED_TEMPERATURE_CAP := 1300.0
const POWERED_TEMPERATURE_CAP := 2000.0
const POWERED_HEAT_MULTIPLIER := 1.25
const POWERED_FUEL_EFFICIENCY_MULTIPLIER := 0.80
const HEAT_EVENT_MIN_TEMP := 160.0
const HEAT_EVENT_MIN_RADIUS := 24.0
const HEAT_EVENT_MAX_RADIUS := 96.0

signal player_entered_range
signal player_exited_range
signal interaction_started
signal interaction_ended
signal temp_changed(current_temp: float)

@export var is_lit := false
@export var fuel_level := 0.0
@export var current_temp := 0.0
@export var target_temp := 0.0
@export var fuel_rate := 0.0
@export var burn_enabled := true

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $PromptLabel

var _unlit_texture: Texture2D
var _lit_texture: Texture2D
var _player_in_range := false
var _is_interacting := false
var _interact_locked_until_release := false
var _player: Node
var _furnace_ui
var _remaining_heat_potential := 0.0
var _remaining_burn_time := 0.0
var _purpose_hint_learned := false
var _fuel_units_burned_since_reaction := 0.0
var _last_fuel_item_id: StringName = &""
var _last_unit_fuel_value := 0.0
var _fuel_slot_state: Dictionary = {
	&"item_id": &"",
	&"quantity": 0,
	&"unit_fuel_value": 0.0,
}
var _power_cell_charge_remaining := 0.0
var _base_grid: Node = null
var _power_switchboard: Node = null
var _input_slots: Dictionary[StringName, Dictionary] = {
	&"input_a": {&"item_id": &"", &"quantity": 0},
	&"input_b": {&"item_id": &"", &"quantity": 0},
}


func _ready() -> void:
	add_to_group(&"heat_source")
	_unlit_texture = _build_placeholder_texture(false)
	_lit_texture = _build_placeholder_texture(true)
	_update_sprite()
	_configure_prompt_label()
	call_deferred("_ensure_ui")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_bind_power_services()
	if not EventBus.service_registered.is_connected(_on_service_registered):
		EventBus.service_registered.connect(_on_service_registered)
	_hide_prompt()


func _process(_delta: float) -> void:
	if _interact_locked_until_release:
		if not Input.is_action_pressed("interact"):
			_interact_locked_until_release = false
		return
	if _player_in_range and not _is_interacting:
		if Input.is_action_just_pressed("interact"):
			_start_interaction()


func _physics_process(delta: float) -> void:
	var remaining_delta := delta

	_drain_power_bonus(delta)

	if burn_enabled and _has_active_fuel():
		remaining_delta = _apply_fuel_heat(delta)

	if remaining_delta > 0.0 and (not _has_active_fuel() or not burn_enabled):
		_apply_cooling(remaining_delta)

	_sync_heat_state()
	temp_changed.emit(current_temp)
	_emit_heat_signature()


func set_lit(value: bool) -> void:
	is_lit = value
	_update_sprite()


func add_fuel(element_id: StringName, qty: int) -> bool:
	if qty <= 0:
		return false

	var fuel_value := ChemistryEngine.get_fuel_value(String(element_id))
	if fuel_value <= 0.0:
		return false

	var active_fuel_id: StringName = _fuel_slot_state.get(&"item_id", &"")
	if not active_fuel_id.is_empty() and active_fuel_id != element_id:
		return false

	_remaining_heat_potential += fuel_value * float(qty)
	_remaining_burn_time += DEFAULT_FUEL_BURN_DURATION * float(qty)
	_fuel_slot_state[&"item_id"] = element_id
	_fuel_slot_state[&"quantity"] = int(_fuel_slot_state.get(&"quantity", 0)) + qty
	_fuel_slot_state[&"unit_fuel_value"] = fuel_value
	_last_fuel_item_id = element_id
	_last_unit_fuel_value = fuel_value
	burn_enabled = true
	_sync_heat_state()
	return true


func insert_power_cell() -> bool:
	return true


func has_power_cell_installed() -> bool:
	return false


func has_power_bonus() -> bool:
	return _is_switchboard_boost_enabled() and _is_base_grid_powered()


func get_power_state() -> Dictionary:
	return {
		&"has_cell": false,
		&"charge_remaining_seconds": 0.0,
		&"switchboard_enabled": _is_switchboard_boost_enabled(),
		&"boost_active": has_power_bonus(),
		&"grid_powered": _is_base_grid_powered(),
	}


func restore_power_state(data: Dictionary) -> void:
	_power_cell_charge_remaining = 0.0
	_sync_ui()


func set_input(slot_name: StringName, element_id: StringName, qty: int) -> bool:
	if qty <= 0 or element_id.is_empty():
		return false

	if slot_name == &"fuel":
		if not add_fuel(element_id, qty):
			return false
		_sync_ui()
		return true

	if not _input_slots.has(slot_name):
		return false
	if ElementDatabase.get_element(element_id).is_empty():
		return false

	var slot_state: Dictionary = _input_slots[slot_name]
	var current_item_id: StringName = slot_state.get(&"item_id", &"")
	var current_quantity := int(slot_state.get(&"quantity", 0))

	if not current_item_id.is_empty() and current_item_id != element_id:
		return false

	slot_state[&"item_id"] = element_id
	slot_state[&"quantity"] = current_quantity + qty
	_input_slots[slot_name] = slot_state
	_sync_ui()
	return true


func get_input(slot_name: StringName) -> Dictionary:
	if not _input_slots.has(slot_name):
		return {}
	return _input_slots[slot_name].duplicate(true)


## Clear an input slot entirely (called by FurnaceUI after smelting consumes inputs).
func clear_input(slot_name: StringName) -> void:
	if not _input_slots.has(slot_name):
		return
	_input_slots[slot_name] = {&"item_id": &"", &"quantity": 0}
	_sync_ui()


func consume_input(slot_name: StringName, qty: int) -> int:
	if qty <= 0 or not _input_slots.has(slot_name):
		return 0

	var slot_state: Dictionary = _input_slots[slot_name]
	var current_item_id: StringName = slot_state.get(&"item_id", &"")
	var current_quantity := int(slot_state.get(&"quantity", 0))
	if current_item_id.is_empty() or current_quantity <= 0:
		return 0

	var consumed_qty := mini(qty, current_quantity)
	var remaining_qty := current_quantity - consumed_qty
	if remaining_qty <= 0:
		_input_slots[slot_name] = {&"item_id": &"", &"quantity": 0}
	else:
		slot_state[&"quantity"] = remaining_qty
		_input_slots[slot_name] = slot_state
	_sync_ui()
	return consumed_qty


func reset_after_explosion() -> void:
	_input_slots[&"input_a"] = {&"item_id": &"", &"quantity": 0}
	_input_slots[&"input_b"] = {&"item_id": &"", &"quantity": 0}
	_remaining_heat_potential = 0.0
	_remaining_burn_time = 0.0
	current_temp = 0.0
	target_temp = 0.0
	fuel_level = 0.0
	fuel_rate = 0.0
	_fuel_units_burned_since_reaction = 0.0
	_last_fuel_item_id = &""
	_last_unit_fuel_value = 0.0
	burn_enabled = true
	_sync_heat_state()
	_sync_ui()
	temp_changed.emit(current_temp)


func get_fuel_state() -> Dictionary:
	if not _has_active_fuel():
		return {&"item_id": &"", &"quantity": 0}

	var fuel_item_id: StringName = _fuel_slot_state.get(&"item_id", &"")
	var unit_fuel_value := float(_fuel_slot_state.get(&"unit_fuel_value", 0.0))
	if fuel_item_id.is_empty() or unit_fuel_value <= 0.0:
		return {&"item_id": &"", &"quantity": 0}

	return {
		&"item_id": fuel_item_id,
		&"quantity": maxi(1, int(ceil(fuel_level / unit_fuel_value))),
	}


func get_fuel_cost_state() -> Dictionary:
	var fuel_item_id: StringName = _fuel_slot_state.get(&"item_id", &"")
	if fuel_item_id.is_empty():
		fuel_item_id = _last_fuel_item_id

	return {
		&"item_id": fuel_item_id,
		&"burned_units": _fuel_units_burned_since_reaction,
	}


func commit_reaction_fuel_cost() -> Dictionary:
	var state := get_fuel_cost_state()
	_fuel_units_burned_since_reaction = 0.0
	_sync_ui()
	return state


func set_burn_enabled(value: bool) -> void:
	burn_enabled = value
	_sync_heat_state()
	_sync_ui()
	temp_changed.emit(current_temp)


func toggle_burn_enabled() -> bool:
	set_burn_enabled(not burn_enabled)
	return burn_enabled


func is_burn_enabled() -> bool:
	return burn_enabled


func open_ui() -> void:
	_purpose_hint_learned = true
	_is_interacting = true
	_interact_locked_until_release = true
	_show_prompt(false)
	if is_instance_valid(_player) and _player.has_method("pause_input"):
		_player.pause_input()
	_ensure_ui()
	if _furnace_ui != null:
		if _furnace_ui.has_method("is_initialized") and not bool(_furnace_ui.is_initialized()):
			call_deferred("open_ui")
			return
		if _furnace_ui.has_method("bind_furnace"):
			_furnace_ui.bind_furnace(self)
		_furnace_ui.open_ui()
	interaction_started.emit()


func close_ui() -> void:
	if not _is_interacting:
		return
	_is_interacting = false
	_interact_locked_until_release = true
	_show_prompt(_player_in_range)
	if _furnace_ui != null:
		_furnace_ui.close_ui()
	if is_instance_valid(_player) and _player.has_method("resume_input"):
		_player.resume_input()
	interaction_ended.emit()


func _start_interaction() -> void:
	open_ui()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player") and body is CharacterBody2D:
		_player = body
		_player_in_range = true
		if not _is_interacting:
			_show_prompt(true)
		player_entered_range.emit()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group(&"player"):
		if body == _player:
			_player = null
		_player_in_range = false
		_hide_prompt()
		player_exited_range.emit()


func _show_prompt(should_show: bool) -> void:
	if prompt_label:
		if should_show:
			prompt_label.text = _get_prompt_text()
		prompt_label.visible = should_show


func _hide_prompt() -> void:
	if prompt_label:
		prompt_label.visible = false


func _configure_prompt_label() -> void:
	if prompt_label == null:
		return
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.offset_left = -98.0
	prompt_label.offset_right = 98.0
	prompt_label.offset_top = -58.0
	prompt_label.offset_bottom = -8.0


func _get_prompt_text() -> String:
	if _purpose_hint_learned or InventoryManager.has_item(CHARCOAL_ITEM_ID, 1):
		return "Press E to use Furnace"
	return "Press E\nBurn fuel into charcoal"


func _ensure_ui() -> void:
	if _furnace_ui != null:
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var ui_parent := current_scene.find_child("HUD", true, false)
	if ui_parent == null:
		ui_parent = current_scene

	_furnace_ui = FURNACE_UI_SCENE.instantiate()
	ui_parent.add_child(_furnace_ui)
	_furnace_ui.ui_closed.connect(_on_ui_closed)
	if _furnace_ui.has_method("bind_furnace"):
		_furnace_ui.bind_furnace(self)
	_sync_ui()


func _on_ui_closed() -> void:
	close_ui()


func _has_active_fuel() -> bool:
	return _remaining_heat_potential > 0.0 and _remaining_burn_time > 0.0


func _apply_fuel_heat(delta: float) -> float:
	var burn_step := minf(delta, _remaining_burn_time)
	if burn_step <= 0.0:
		return delta

	fuel_rate = _remaining_heat_potential / _remaining_burn_time
	target_temp = current_temp + _remaining_heat_potential

	var heat_multiplier := POWERED_HEAT_MULTIPLIER if has_power_bonus() else 1.0
	var effective_temperature_cap := POWERED_TEMPERATURE_CAP if has_power_bonus() else UNPOWERED_TEMPERATURE_CAP
	var rise_amount := fuel_rate * burn_step * heat_multiplier
	var capped_target_temp := minf(target_temp, effective_temperature_cap)
	current_temp = minf(effective_temperature_cap, move_toward(current_temp, capped_target_temp, rise_amount))
	var heat_consumed := rise_amount
	if current_temp >= effective_temperature_cap and target_temp > effective_temperature_cap:
		heat_consumed = minf(heat_consumed, maxf(0.0, effective_temperature_cap - (current_temp - rise_amount)))
	var heat_cost_multiplier := POWERED_FUEL_EFFICIENCY_MULTIPLIER if has_power_bonus() else 1.0
	var consumed_heat_potential := heat_consumed * heat_cost_multiplier
	var unit_fuel_value := float(_fuel_slot_state.get(&"unit_fuel_value", 0.0))
	if unit_fuel_value > 0.0:
		_fuel_units_burned_since_reaction += consumed_heat_potential / unit_fuel_value
	_remaining_heat_potential = maxf(0.0, _remaining_heat_potential - consumed_heat_potential)
	_remaining_burn_time = maxf(0.0, _remaining_burn_time - burn_step)

	return delta - burn_step


func _apply_cooling(delta: float) -> void:
	current_temp = maxf(0.0, current_temp - (PASSIVE_COOL_RATE * delta))


func _sync_heat_state() -> void:
	fuel_level = _remaining_heat_potential

	if _has_active_fuel():
		fuel_rate = _remaining_heat_potential / _remaining_burn_time
		target_temp = current_temp + _remaining_heat_potential
		set_lit(burn_enabled)
		return

	_remaining_heat_potential = 0.0
	_remaining_burn_time = 0.0
	fuel_level = 0.0
	fuel_rate = 0.0
	target_temp = 0.0
	_fuel_slot_state = {
		&"item_id": &"",
		&"quantity": 0,
		&"unit_fuel_value": 0.0,
	}
	set_lit(false)


func _sync_ui() -> void:
	if _furnace_ui == null:
		return

	var input_a: Dictionary = _input_slots.get(&"input_a", {})
	var input_b: Dictionary = _input_slots.get(&"input_b", {})

	if _furnace_ui.has_method("set_input_slot_a"):
		_furnace_ui.set_input_slot_a(
			input_a.get(&"item_id", &""),
			int(input_a.get(&"quantity", 0))
		)
	if _furnace_ui.has_method("set_input_slot_b"):
		_furnace_ui.set_input_slot_b(
			input_b.get(&"item_id", &""),
			int(input_b.get(&"quantity", 0))
		)
	if _furnace_ui.has_method("set_fuel_slot"):
		var fuel_state := get_fuel_state()
		_furnace_ui.set_fuel_slot(
			fuel_state.get(&"item_id", &""),
			int(fuel_state.get(&"quantity", 0))
		)
	if _furnace_ui.has_method("set_burn_enabled"):
		_furnace_ui.set_burn_enabled(burn_enabled)
	if _furnace_ui.has_method("set_fuel_cost_state"):
		_furnace_ui.set_fuel_cost_state(get_fuel_cost_state())
	if _furnace_ui.has_method("set_power_state"):
		_furnace_ui.set_power_state(get_power_state())


func _update_sprite() -> void:
	if sprite == null:
		return
	sprite.texture = _lit_texture if is_lit else _unlit_texture


func _build_placeholder_texture(lit: bool) -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var brick := Color8(92, 88, 80)
	var shadow := Color8(54, 50, 45)
	var top := Color8(124, 118, 108)
	var mouth := Color8(28, 23, 20)
	var glow := Color8(255, 145, 50)
	var ember := Color8(255, 215, 110)

	for y in range(6, 29):
		for x in range(5, 27):
			image.set_pixel(x, y, brick)

	for y in range(6, 10):
		for x in range(8, 24):
			image.set_pixel(x, y, top)

	for y in range(10, 29):
		image.set_pixel(5, y, shadow)
		image.set_pixel(26, y, shadow)

	for x in range(5, 27):
		image.set_pixel(x, 28, shadow)

	for y in range(15, 25):
		for x in range(10, 22):
			image.set_pixel(x, y, mouth)

	var fire_color := glow if lit else shadow
	for y in range(17, 24):
		for x in range(12, 20):
			image.set_pixel(x, y, fire_color)

	if lit:
		for y in range(19, 22):
			for x in range(14, 18):
				image.set_pixel(x, y, ember)

	for y in range(3, 7):
		for x in range(20, 24):
			image.set_pixel(x, y, shadow)

	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _drain_power_bonus(delta: float) -> void:
	return


func _is_switchboard_boost_enabled() -> bool:
	if _power_switchboard == null or not _power_switchboard.has_method("allows_furnace_boost"):
		return true
	return bool(_power_switchboard.allows_furnace_boost())


func _is_base_grid_powered() -> bool:
	if _base_grid == null or not _base_grid.has_method("is_powered"):
		return false
	return bool(_base_grid.is_powered())


func _on_service_registered(service_id: StringName, _service: Node) -> void:
	if service_id == EventBus.SERVICE_BASE_GRID or service_id == EventBus.SERVICE_POWER_SWITCHBOARD:
		_bind_power_services()


func _bind_power_services() -> void:
	_base_grid = EventBus.get_base_grid()
	_power_switchboard = EventBus.get_power_switchboard()
	if _power_switchboard != null and _power_switchboard.has_signal("switchboard_changed"):
		if not _power_switchboard.switchboard_changed.is_connected(_sync_ui):
			_power_switchboard.switchboard_changed.connect(_sync_ui)


func _emit_heat_signature() -> void:
	if current_temp < HEAT_EVENT_MIN_TEMP:
		return
	if ChemistryEngine == null or not ChemistryEngine.has_method("emit_heat_event"):
		return
	var intensity := clampf(current_temp / POWERED_TEMPERATURE_CAP, 0.0, 1.0)
	var radius := lerpf(HEAT_EVENT_MIN_RADIUS, HEAT_EVENT_MAX_RADIUS, intensity)
	ChemistryEngine.emit_heat_event(self, radius, intensity)
