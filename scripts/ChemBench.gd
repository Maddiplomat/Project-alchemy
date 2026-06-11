extends StaticBody2D

const CHEM_BENCH_UI_SCENE := preload("res://scenes/UI/ChemBenchUI.tscn")
const CHEMICAL_EXPLOSION_SCENE := preload("res://scenes/ChemicalExplosion.tscn")
const SHRAPNEL_BURST_SCENE := preload("res://scenes/ShrapnelBurst.tscn")
const TOXIC_CLOUD_SCENE := preload("res://scenes/ToxicCloud.tscn")
const DISTILLATION_KIT_ITEM_ID := &"distillation_kit"
const SLOT_INPUT_A := &"input_a"
const SLOT_INPUT_B := &"input_b"
const SLOT_CATALYST := &"catalyst"
const RATIO_TARGET_INPUT_A := SLOT_INPUT_A
const RATIO_TARGET_INPUT_B := SLOT_INPUT_B
const DEFAULT_RATIO_PERCENT := 50.0
const DEFAULT_TEMPERATURE_C := 90.0
const MIN_TEMPERATURE_C := 20.0
const MAX_TEMPERATURE_C := 260.0
const POWER_CELL_DURATION_SECONDS := 480.0

signal player_entered_range
signal player_exited_range
signal interaction_started
signal interaction_ended
signal state_changed

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: Label = $PromptLabel

var _player_in_range := false
var _is_interacting := false
var _interact_locked_until_release := false
var _player: Node = null
var _chem_bench_ui
var _purpose_hint_learned := false
var _slot_state: Dictionary[StringName, Dictionary] = {
	SLOT_INPUT_A: {&"item_id": &"", &"quantity": 0},
	SLOT_INPUT_B: {&"item_id": &"", &"quantity": 0},
	SLOT_CATALYST: {&"item_id": &"", &"quantity": 0},
}
var _ratio_target_slot: StringName = RATIO_TARGET_INPUT_B
var _ratio_percent := DEFAULT_RATIO_PERCENT
var _temperature_c := DEFAULT_TEMPERATURE_C
var _power_cell_charge_remaining := 0.0


func _ready() -> void:
	sprite.texture = _build_placeholder_texture()
	_apply_visual_identity()
	_configure_prompt_label()
	call_deferred("_ensure_ui")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_hide_prompt()


func _process(_delta: float) -> void:
	_drain_power_bonus(_delta)
	if _interact_locked_until_release:
		if not Input.is_action_pressed("interact"):
			_interact_locked_until_release = false
		return

	if _player_in_range and not _is_interacting and Input.is_action_just_pressed("interact"):
		_start_interaction()


func open_ui() -> void:
	_purpose_hint_learned = true
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


func get_input(slot_id: StringName) -> Dictionary:
	if not _slot_state.has(slot_id):
		return {}
	return _slot_state[slot_id].duplicate(true)


func set_input(slot_id: StringName, item_id: StringName, qty: int) -> bool:
	if qty <= 0 or item_id.is_empty():
		return false
	if not _slot_state.has(slot_id):
		return false
	if slot_id == SLOT_CATALYST:
		if not _can_accept_catalyst_item(item_id):
			return false
	elif not _can_accept_reactant_item(item_id):
		return false

	var slot_state: Dictionary = _slot_state[slot_id]
	var current_item_id: StringName = slot_state.get(&"item_id", &"")
	if not current_item_id.is_empty() and current_item_id != item_id:
		return false

	slot_state[&"item_id"] = item_id
	slot_state[&"quantity"] = int(slot_state.get(&"quantity", 0)) + qty
	_slot_state[slot_id] = slot_state
	_emit_state_changed()
	return true


func consume_input(slot_id: StringName, qty: int) -> int:
	if qty <= 0 or not _slot_state.has(slot_id):
		return 0

	var slot_state: Dictionary = _slot_state[slot_id]
	var item_id: StringName = slot_state.get(&"item_id", &"")
	var current_quantity := int(slot_state.get(&"quantity", 0))
	if item_id.is_empty() or current_quantity <= 0:
		return 0

	var consumed_qty := mini(qty, current_quantity)
	var remaining_qty := current_quantity - consumed_qty
	if remaining_qty <= 0:
		_slot_state[slot_id] = {&"item_id": &"", &"quantity": 0}
	else:
		slot_state[&"quantity"] = remaining_qty
		_slot_state[slot_id] = slot_state
	_emit_state_changed()
	return consumed_qty


func clear_input(slot_id: StringName) -> void:
	if not _slot_state.has(slot_id):
		return
	if int(_slot_state[slot_id].get(&"quantity", 0)) <= 0 and StringName(_slot_state[slot_id].get(&"item_id", &"")).is_empty():
		return
	_slot_state[slot_id] = {&"item_id": &"", &"quantity": 0}
	_emit_state_changed()


func clear_all_inputs() -> void:
	var changed := false
	for slot_id: StringName in _slot_state.keys():
		var item_id := StringName(_slot_state[slot_id].get(&"item_id", &""))
		var quantity := int(_slot_state[slot_id].get(&"quantity", 0))
		if item_id.is_empty() and quantity <= 0:
			continue
		_slot_state[slot_id] = {&"item_id": &"", &"quantity": 0}
		changed = true
	if changed:
		_emit_state_changed()


func get_ratio_percent() -> float:
	return _ratio_percent


func get_ratio_target_slot() -> StringName:
	return _ratio_target_slot


func set_ratio_target_slot(slot_id: StringName) -> void:
	var normalized_slot := _normalize_ratio_target_slot(slot_id)
	if _ratio_target_slot == normalized_slot:
		return
	_ratio_target_slot = normalized_slot
	_emit_state_changed()


func set_ratio_percent(value: float) -> void:
	var clamped := clampf(value, 0.0, 100.0)
	if is_equal_approx(_ratio_percent, clamped):
		return
	_ratio_percent = clamped
	_emit_state_changed()


func get_temperature() -> float:
	return _temperature_c


func set_temperature(value: float) -> void:
	var clamped := clampf(value, MIN_TEMPERATURE_C, MAX_TEMPERATURE_C)
	if is_equal_approx(_temperature_c, clamped):
		return
	_temperature_c = clamped
	_emit_state_changed()


func evaluate_current_reaction() -> Dictionary:
	return ChemistryEngine.evaluate_chem_bench_reaction(_build_reaction_state())


func can_accept_reactant(item_id: StringName) -> bool:
	return _can_accept_reactant_item(item_id)


func can_accept_catalyst(item_id: StringName) -> bool:
	return _can_accept_catalyst_item(item_id)


func trigger_stabilization_failure(reason: StringName) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		current_scene = get_tree().root

	match reason:
		&"heat_runaway":
			var explosion := CHEMICAL_EXPLOSION_SCENE.instantiate() as Node2D
			current_scene.add_child(explosion)
			explosion.global_position = global_position
		&"pressure_spike":
			var shrapnel_burst := SHRAPNEL_BURST_SCENE.instantiate() as Node2D
			current_scene.add_child(shrapnel_burst)
			shrapnel_burst.global_position = global_position
		&"timer_expiry":
			var toxic_cloud := TOXIC_CLOUD_SCENE.instantiate() as Node2D
			current_scene.add_child(toxic_cloud)
			toxic_cloud.global_position = global_position


func get_ui_state() -> Dictionary:
	var result: Dictionary = {
		&"ratio_target_slot": _ratio_target_slot,
		&"ratio_percent": _ratio_percent,
		&"temperature_c": _temperature_c,
		&"power_state": get_power_state(),
	}
	for slot_id: StringName in _slot_state.keys():
		result[slot_id] = get_input(slot_id)
	return result


func insert_power_cell() -> bool:
	if has_power_bonus():
		return false
	if not InventoryManager.has_item(&"energy_cell", 1):
		return false
	InventoryManager.remove_item(&"energy_cell", 1)
	_power_cell_charge_remaining = POWER_CELL_DURATION_SECONDS
	_emit_state_changed()
	return true


func has_power_bonus() -> bool:
	return _power_cell_charge_remaining > 0.0


func get_power_state() -> Dictionary:
	return {
		&"has_cell": has_power_bonus(),
		&"charge_remaining_seconds": _power_cell_charge_remaining,
	}


func restore_power_state(data: Dictionary) -> void:
	_power_cell_charge_remaining = clampf(float(data.get(&"charge_remaining_seconds", 0.0)), 0.0, POWER_CELL_DURATION_SECONDS)
	_emit_state_changed()


func _build_reaction_state() -> Dictionary:
	return {
		&"input_a": get_input(SLOT_INPUT_A),
		&"input_b": get_input(SLOT_INPUT_B),
		&"catalyst": get_input(SLOT_CATALYST),
		&"ratio_target_slot": _ratio_target_slot,
		&"ratio_percent": _ratio_percent,
		&"temperature_c": _temperature_c,
	}


func _can_accept_reactant_item(item_id: StringName) -> bool:
	var element_data := ElementDatabase.get_element(item_id)
	if element_data.is_empty():
		return false
	return ChemistryEngine.can_use_chem_bench_reactant(item_id)


func _can_accept_catalyst_item(item_id: StringName) -> bool:
	var element_data := ElementDatabase.get_element(item_id)
	if element_data.is_empty():
		return false
	return str(element_data.get(&"category", "")) == "catalyst"


func _normalize_ratio_target_slot(slot_id: StringName) -> StringName:
	if slot_id == RATIO_TARGET_INPUT_A:
		return RATIO_TARGET_INPUT_A
	return RATIO_TARGET_INPUT_B


func _emit_state_changed() -> void:
	GameManager.mark_dirty()
	state_changed.emit()


func _drain_power_bonus(delta: float) -> void:
	if not has_power_bonus() or not _is_interacting:
		return
	var previous_charge := _power_cell_charge_remaining
	_power_cell_charge_remaining = maxf(0.0, _power_cell_charge_remaining - delta)
	if is_equal_approx(previous_charge, _power_cell_charge_remaining):
		return
	_emit_state_changed()


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
		if should_show:
			prompt_label.text = _get_prompt_text()
		prompt_label.visible = should_show


func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.visible = false


func _configure_prompt_label() -> void:
	if prompt_label == null:
		return
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.offset_left = -104.0
	prompt_label.offset_right = 104.0
	prompt_label.offset_top = -58.0
	prompt_label.offset_bottom = -8.0


func _get_prompt_text() -> String:
	if _purpose_hint_learned or InventoryManager.has_item(DISTILLATION_KIT_ITEM_ID, 1):
		return "Press E to use ChemBench"
	return "Press E\nCraft a kit before sulfur"


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
