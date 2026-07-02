extends Node

const InventoryItemData = preload("res://scripts/InventoryItem.gd")

signal inventory_changed(slot_index: int)
signal active_slot_changed(new_index: int)
signal weight_changed(total_weight: float, carry_capacity: float)
signal purity_changed(slot_index: int, new_purity: float)

signal item_added(item_id: StringName, quantity: int, total_quantity: int)
signal item_removed(item_id: StringName, quantity: int, remaining_quantity: int)
signal item_quantity_changed(item_id: StringName, quantity: int)
signal held_item_changed(item_id: StringName)
signal capacity_changed(total_weight: float, carry_capacity: float)
signal volatile_risk_changed(risk_item_ids: Array[StringName])

const MAX_SLOTS := 5 # Intentional current vertical-slice field loadout target.
const DEFAULT_SLOT_COUNT := MAX_SLOTS
const DEFAULT_ITEM_WEIGHT := 1.0
const DEFAULT_ITEM_PURITY := 1.0
const DEFAULT_ITEM_DURABILITY := 1.0
const DEFAULT_ITEM_MAX_DURABILITY := 1.0
const DEFAULT_LITHIUM_CHARGE := 1.0
const NO_ITEM := &""
const LITHIUM_ITEM_ID := &"lithium"
const SULFUR_ITEM_ID := &"sulfur"
const LITHIUM_RAIN_PURITY_LOSS_PER_SECOND := 0.02
const LITHIUM_STORM_CHARGE_GAIN_PER_SECOND := 0.01
const HEAT_SOURCE_TTL_SECONDS := 0.25
const SULFUR_HEAT_REASON := "Sulfur is heating near an active furnace."

enum InventoryItemCategory { GENERIC, ELEMENT, TOOL, CRAFTED, CONSUMABLE }
enum InventoryRiskLevel { NONE, LOW, MEDIUM, HIGH, EXTREME }

var carry_capacity := 20.0
var total_weight := 0.0
var active_slot_index := 0

var slots: Array[Dictionary] = []
var items: Dictionary = {}
var volatile_risk_item_ids: Array[StringName] = []
var _heat_sources: Dictionary = {}
var _sulfur_heat_risk_active := false


func _ready() -> void:
	_initialize_slots()
	_sync_weight_state()
	if WeatherSystem != null and WeatherSystem.has_signal("weather_tick"):
		WeatherSystem.weather_tick.connect(_on_weather_tick)
	if ChemistryEngine != null and ChemistryEngine.has_signal("heat_event"):
		ChemistryEngine.heat_event.connect(_on_heat_event)


func _physics_process(_delta: float) -> void:
	_cleanup_heat_sources()
	_update_sulfur_heat_risk()


func add_element(id: StringName, qty: int, purity: float) -> bool:
	var item_data := ElementDatabase.get_element(id)
	if item_data.is_empty():
		return false

	var normalized := item_data.duplicate(true)
	normalized["id"] = id
	normalized["purity"] = purity
	normalized["category"] = InventoryItemCategory.ELEMENT
	normalized["risk_level"] = _to_inventory_risk_level(item_data.get(&"carrier_risk"))
	return add_item(normalized, qty)


func add_item(item_data, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var normalized = _normalize_item_data(item_data, quantity)
	var item_id = StringName(normalized.id)
	if item_id.is_empty():
		return false

	var slot_index := _find_slot_for_item(item_id)
	if slot_index == -1:
		slot_index = _find_free_slot()
		if slot_index == -1:
			return false

	var previous_active_item := _get_active_item_id()
	var previous_quantity := 0
	var previous_purity := 0.0
	if slot_index >= 0 and slots[slot_index]["item_id"] == item_id:
		previous_quantity = int(slots[slot_index]["quantity"])
		previous_purity = float(slots[slot_index]["purity"])

	var next_quantity := previous_quantity + quantity
	var next_purity := _combine_purity(previous_purity, previous_quantity, normalized.purity, quantity)

	slots[slot_index] = {
		"item_id": item_id,
		"quantity": next_quantity,
		"purity": next_purity,
	}

	var stored_item = _get_stored_item(item_id)
	if stored_item == null:
		stored_item = normalized.duplicate_item()
	else:
		stored_item = stored_item.duplicate_item()
		stored_item.merge_metadata_from(normalized)
	stored_item.id = item_id
	stored_item.item_id = item_id
	stored_item.quantity = next_quantity
	stored_item.purity = next_purity
	stored_item.unit_weight = _get_stack_unit_weight(item_id, stored_item)
	stored_item.weight = stored_item.unit_weight
	items[item_id] = stored_item

	_post_slot_mutation([slot_index], previous_active_item)
	item_added.emit(item_id, quantity, next_quantity)
	item_quantity_changed.emit(item_id, next_quantity)
	if not is_equal_approx(previous_purity, next_purity):
		purity_changed.emit(slot_index, next_purity)
	return true


func remove_element(id: StringName, qty: int) -> void:
	remove_item(id, qty)


func remove_item(item_id: StringName, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false
	if not items.has(item_id):
		return false

	var slot_index := _find_slot_for_item(item_id)
	if slot_index == -1:
		items.erase(item_id)
		_post_metadata_mutation(NO_ITEM)
		return false

	var slot := slots[slot_index]
	var current_quantity_in_slot := int(slot["quantity"])
	if quantity > current_quantity_in_slot:
		return false

	var previous_active_item := _get_active_item_id()
	var remaining_quantity := current_quantity_in_slot - quantity

	if remaining_quantity <= 0:
		slots[slot_index] = _make_empty_slot()
		items.erase(item_id)
	else:
		slot["quantity"] = remaining_quantity
		slots[slot_index] = slot

		var stored_item = _get_stored_item(item_id)
		stored_item.quantity = remaining_quantity
		stored_item.purity = float(slot["purity"])
		items[item_id] = stored_item

	_post_slot_mutation([slot_index], previous_active_item)
	item_removed.emit(item_id, quantity, remaining_quantity)
	item_quantity_changed.emit(item_id, remaining_quantity)
	return true


func get_stack(id: StringName) -> Dictionary:
	var item_id := StringName(String(id))
	if not items.has(item_id):
		return {"quantity": 0, "purity": 0.0}
	return _get_stored_item(item_id).to_dict()


func get_all_items() -> Dictionary:
	var ordered_items := {}
	for slot in slots:
		var item_id: StringName = slot["item_id"]
		if item_id.is_empty() or not items.has(item_id):
			continue
		ordered_items[String(item_id)] = _get_stored_item(item_id).to_dict()
	for item_id: StringName in items.keys():
		if not ordered_items.has(String(item_id)):
			ordered_items[String(item_id)] = _get_stored_item(item_id).to_dict()
	return ordered_items


func get_items() -> Dictionary:
	var result := {}
	for item_id: StringName in items.keys():
		result[item_id] = _get_stored_item(item_id).to_dict()
	return result


func get_slot_data(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return _empty_slot_data()

	var slot := slots[slot_index]
	var item_id: StringName = slot["item_id"]
	if item_id.is_empty():
		return _empty_slot_data()

	var merged := {}
	var stored_item = _get_stored_item(item_id)
	if stored_item != null:
		merged = stored_item.to_dict()
	merged["id"] = item_id
	merged["item_id"] = item_id
	merged["quantity"] = int(slot["quantity"])
	merged["purity"] = float(slot["purity"])
	return merged


func get_slot_item(slot_index: int) -> Dictionary:
	var data := get_slot_data(slot_index)
	if StringName(data.get("item_id", NO_ITEM)).is_empty():
		return {}
	return data


func set_active_slot(index: int) -> void:
	var next_index := clampi(index, 0, MAX_SLOTS - 1)
	if next_index == active_slot_index:
		return

	active_slot_index = next_index
	active_slot_changed.emit(active_slot_index)
	held_item_changed.emit(_get_active_item_id())


func select_slot(slot_index: int) -> void:
	set_active_slot(slot_index)


func set_held_item(item_id: StringName, _manual: bool = false) -> bool:
	if item_id.is_empty():
		held_item_changed.emit(_get_active_item_id())
		return true

	var slot_index := _find_slot_for_item(item_id)
	if slot_index == -1:
		return false

	set_active_slot(slot_index)
	return true


func get_held_item_id() -> String:
	return String(_get_active_item_id())


func get_held_item() -> Dictionary:
	return get_slot_item(active_slot_index)


func has_item(item_id: StringName, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true
	return get_quantity(item_id) >= quantity


func get_quantity(item_id: StringName) -> int:
	if not items.has(item_id):
		return 0
	var stored_item = _get_stored_item(item_id)
	if stored_item == null:
		return 0
	return stored_item.quantity


func can_add_item(item_data, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var normalized = _normalize_item_data(item_data, quantity)
	var item_id = StringName(normalized.id)
	if item_id.is_empty():
		return false

	if _find_slot_for_item(item_id) == -1 and _find_free_slot() == -1:
		return false

	var added_weight := _get_stack_unit_weight(item_id, normalized) * float(quantity)
	if total_weight < carry_capacity:
		return true
	return total_weight + added_weight <= carry_capacity


func is_over_capacity() -> bool:
	return total_weight > carry_capacity


func lose_random_item() -> void:
	var occupied_slots := _get_occupied_slots()
	if occupied_slots.is_empty():
		return

	var slot_index := occupied_slots[randi() % occupied_slots.size()]
	var item_id: StringName = slots[slot_index]["item_id"]
	remove_item(item_id, 1)


func destroy_random_occupied_slot() -> Dictionary:
	var occupied_slots := _get_occupied_slots()
	if occupied_slots.is_empty():
		return {}

	var slot_index := occupied_slots[randi() % occupied_slots.size()]
	var slot_data := get_slot_data(slot_index)
	if slot_data.is_empty():
		return {}

	var item_id := StringName(slot_data.get("item_id", NO_ITEM))
	var quantity := int(slot_data.get("quantity", 0))
	if item_id.is_empty() or quantity <= 0:
		return {}

	if not remove_item(item_id, quantity):
		return {}

	return {
		"slot_index": slot_index,
		"item_id": item_id,
		"quantity": quantity,
	}


func receive_world_pickup(item_data, quantity: int = 1) -> bool:
	var normalized_pickup := _variant_to_dict(item_data)
	var pickup_item = InventoryItemData.from_variant(normalized_pickup)
	var item_id = StringName(pickup_item.id)
	if item_id.is_empty():
		return false

	normalized_pickup["id"] = item_id
	normalized_pickup["item_id"] = item_id
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		normalized_pickup["purity"] = clampf(pickup_item.purity, 0.0, 1.0)
		normalized_pickup["category"] = InventoryItemCategory.ELEMENT
		normalized_pickup["risk_level"] = _to_inventory_risk_level(element_data.get(&"carrier_risk"))
	return add_item(normalized_pickup, quantity)


func degrade_item(item_id: StringName, amount: float) -> bool:
	if amount <= 0.0 or not items.has(item_id):
		return false

	var stored_item = _get_stored_item(item_id)
	if stored_item == null or not stored_item.has_durability:
		return false

	var current_durability = float(stored_item.durability)
	var max_durability := maxf(0.0, stored_item.max_durability)
	var next_durability := clampf(current_durability - amount, 0.0, max_durability)
	if is_equal_approx(current_durability, next_durability):
		return false

	if next_durability <= 0.0:
		return remove_item(item_id, stored_item.quantity)

	stored_item.durability = next_durability
	items[item_id] = stored_item
	_post_metadata_mutation(_get_active_item_id())
	var slot_index := _find_slot_for_item(item_id)
	if slot_index != -1:
		inventory_changed.emit(slot_index)
	return true


func get_item_charge(item_id: StringName) -> float:
	if not items.has(item_id):
		return 0.0
	return clampf(_get_stored_item(item_id).charge, 0.0, 1.0)


func drain_lithium_charge(amount: float) -> float:
	if amount <= 0.0 or not items.has(LITHIUM_ITEM_ID):
		return get_item_charge(LITHIUM_ITEM_ID)

	var stored_item = _get_stored_item(LITHIUM_ITEM_ID)
	var current_charge := clampf(stored_item.charge, 0.0, 1.0)
	var next_charge := clampf(current_charge - amount, 0.0, 1.0)
	if is_equal_approx(current_charge, next_charge):
		return next_charge

	stored_item.charge = next_charge
	items[LITHIUM_ITEM_ID] = stored_item
	_post_metadata_mutation(_get_active_item_id())
	var slot_index := _find_slot_for_item(LITHIUM_ITEM_ID)
	if slot_index != -1:
		inventory_changed.emit(slot_index)
	return next_charge


func charge_lithium(amount: float) -> float:
	if amount <= 0.0 or not items.has(LITHIUM_ITEM_ID):
		return get_item_charge(LITHIUM_ITEM_ID)

	var stored_item = _get_stored_item(LITHIUM_ITEM_ID)
	var max_charge := clampf(stored_item.max_charge, 0.0, 1.0)
	var current_charge := clampf(stored_item.charge, 0.0, max_charge)
	var next_charge := clampf(current_charge + amount, 0.0, max_charge)
	if is_equal_approx(current_charge, next_charge):
		return next_charge

	stored_item.charge = next_charge
	items[LITHIUM_ITEM_ID] = stored_item
	_post_metadata_mutation(_get_active_item_id())
	var slot_index := _find_slot_for_item(LITHIUM_ITEM_ID)
	if slot_index != -1:
		inventory_changed.emit(slot_index)
	return next_charge


func set_max_weight(value: float) -> void:
	carry_capacity = maxf(0.0, value)
	_emit_weight_signals()
	_mark_game_dirty()


func get_capacity_ratio() -> float:
	if is_zero_approx(carry_capacity):
		return 1.0
	return clampf(total_weight / carry_capacity, 0.0, 1.0)


func swap_slots(from_slot: int, to_slot: int) -> void:
	if from_slot < 0 or from_slot >= MAX_SLOTS:
		return
	if to_slot < 0 or to_slot >= MAX_SLOTS:
		return
	if from_slot == to_slot:
		return

	var previous_active_item := _get_active_item_id()
	var temp := slots[from_slot]
	slots[from_slot] = slots[to_slot]
	slots[to_slot] = temp
	inventory_changed.emit(from_slot)
	inventory_changed.emit(to_slot)
	_post_metadata_mutation(previous_active_item)


func move_item_to_slot(item_id: StringName, target_slot: int) -> void:
	if item_id.is_empty():
		return
	if target_slot < 0 or target_slot >= MAX_SLOTS:
		return

	var current_slot := _find_slot_for_item(item_id)
	if current_slot == -1 or current_slot == target_slot:
		return
	swap_slots(current_slot, target_slot)


func clear_inventory() -> void:
	var had_items := not items.is_empty()
	items.clear()
	volatile_risk_item_ids.clear()
	_heat_sources.clear()
	_set_sulfur_heat_risk_active(false)
	_initialize_slots()
	_sync_weight_state()

	for slot_index in range(MAX_SLOTS):
		inventory_changed.emit(slot_index)

	if had_items:
		held_item_changed.emit(_get_active_item_id())
		volatile_risk_changed.emit([])

	_emit_weight_signals()
	_mark_game_dirty()


func _initialize_slots() -> void:
	slots.clear()
	for _slot_index in range(MAX_SLOTS):
		slots.append(_make_empty_slot())


func _make_empty_slot() -> Dictionary:
	return {
		"item_id": NO_ITEM,
		"quantity": 0,
		"purity": 0.0,
	}


func _empty_slot_data() -> Dictionary:
	return {
		"id": NO_ITEM,
		"item_id": NO_ITEM,
		"quantity": 0,
		"purity": 0.0,
	}


func _normalize_item_data(item_data, quantity: int):
	var normalized = InventoryItemData.from_variant(item_data, {
		&"id": NO_ITEM,
		&"quantity": quantity,
		&"purity": DEFAULT_ITEM_PURITY,
		&"category": InventoryItemCategory.GENERIC,
		&"risk_level": InventoryRiskLevel.NONE,
		&"unit_weight": DEFAULT_ITEM_WEIGHT,
		&"charge": DEFAULT_LITHIUM_CHARGE,
		&"max_charge": DEFAULT_LITHIUM_CHARGE,
		&"durability": DEFAULT_ITEM_DURABILITY,
		&"max_durability": DEFAULT_ITEM_MAX_DURABILITY,
	})
	normalized.item_id = normalized.id
	normalized.quantity = quantity
	normalized.purity = clampf(normalized.purity, 0.0, 1.0)
	normalized.category = _normalize_inventory_category(normalized.category)
	normalized.risk_level = int(normalized.risk_level)
	normalized.unit_weight = _get_stack_unit_weight(normalized.id, normalized)
	normalized.weight = normalized.unit_weight

	if normalized.id == LITHIUM_ITEM_ID:
		normalized.charge = clampf(normalized.charge, 0.0, 1.0)
		normalized.max_charge = clampf(normalized.max_charge, 0.0, 1.0)

	if normalized.category == InventoryItemCategory.ELEMENT or normalized.category == InventoryItemCategory.CONSUMABLE:
		normalized.has_durability = false
	else:
		normalized.has_durability = true
		normalized.max_durability = maxf(0.0, normalized.max_durability)
		normalized.durability = clampf(normalized.durability, 0.0, normalized.max_durability)

	return normalized


func _get_stack_unit_weight(item_id: StringName, item_data) -> float:
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return maxf(0.0, float(element_data.get(&"weight", DEFAULT_ITEM_WEIGHT)))
	var inventory_item = InventoryItemData.from_variant(item_data, {&"unit_weight": DEFAULT_ITEM_WEIGHT})
	return maxf(0.0, inventory_item.unit_weight if inventory_item.unit_weight > 0.0 else inventory_item.weight)


func _combine_purity(existing_purity: float, existing_quantity: int, added_purity: float, added_quantity: int) -> float:
	if existing_quantity <= 0:
		return clampf(added_purity, 0.0, 1.0)

	var total_quantity := existing_quantity + added_quantity
	if total_quantity <= 0:
		return 0.0

	return clampf(
		((existing_purity * float(existing_quantity)) + (added_purity * float(added_quantity))) / float(total_quantity),
		0.0,
		1.0
	)


func _normalize_inventory_category(category_value) -> int:
	if category_value is int:
		return category_value

	match String(category_value).to_lower():
		"element":
			return InventoryItemCategory.ELEMENT
		"tool":
			return InventoryItemCategory.TOOL
		"crafted":
			return InventoryItemCategory.CRAFTED
		"consumable":
			return InventoryItemCategory.CONSUMABLE
		_:
			return InventoryItemCategory.GENERIC


func _to_inventory_risk_level(risk_level_name) -> int:
	match str(risk_level_name).to_lower():
		"low":
			return InventoryRiskLevel.LOW
		"medium":
			return InventoryRiskLevel.MEDIUM
		"high":
			return InventoryRiskLevel.HIGH
		"extreme":
			return InventoryRiskLevel.EXTREME
		_:
			return InventoryRiskLevel.NONE


func _find_slot_for_item(item_id: StringName) -> int:
	for slot_index in range(MAX_SLOTS):
		if slots[slot_index]["item_id"] == item_id and int(slots[slot_index]["quantity"]) > 0:
			return slot_index
	return -1


func _find_free_slot() -> int:
	for slot_index in range(MAX_SLOTS):
		if StringName(slots[slot_index]["item_id"]).is_empty() or int(slots[slot_index]["quantity"]) <= 0:
			return slot_index
	return -1


func _get_occupied_slots() -> Array[int]:
	var occupied_slots: Array[int] = []
	for slot_index in range(MAX_SLOTS):
		if int(slots[slot_index]["quantity"]) > 0 and not StringName(slots[slot_index]["item_id"]).is_empty():
			occupied_slots.append(slot_index)
	return occupied_slots


func _get_active_item_id() -> StringName:
	var active_data := get_slot_data(active_slot_index)
	return StringName(active_data.get("item_id", NO_ITEM))


func _post_slot_mutation(changed_slots: Array[int], previous_active_item: StringName) -> void:
	_sync_weight_state()
	_emit_weight_signals()
	_recalculate_volatile_risk()
	for slot_index in changed_slots:
		inventory_changed.emit(slot_index)
	_sync_active_item_signal(previous_active_item)
	_mark_game_dirty()


func _post_metadata_mutation(previous_active_item: StringName) -> void:
	_sync_weight_state()
	_emit_weight_signals()
	_recalculate_volatile_risk()
	_sync_active_item_signal(previous_active_item)
	_mark_game_dirty()


func _sync_weight_state() -> void:
	var recalculated_weight := 0.0
	for item_id: StringName in items.keys():
		var stored_item = _get_stored_item(item_id)
		recalculated_weight += _get_stack_unit_weight(item_id, stored_item) * float(stored_item.quantity)
	total_weight = recalculated_weight


func _emit_weight_signals() -> void:
	capacity_changed.emit(total_weight, carry_capacity)
	weight_changed.emit(total_weight, carry_capacity)


func _recalculate_volatile_risk() -> void:
	var next_risk_item_ids: Array[StringName] = []
	for item_id: StringName in items.keys():
		if _is_risky_item(item_id, _get_stored_item(item_id)):
			next_risk_item_ids.append(item_id)
	if volatile_risk_item_ids == next_risk_item_ids:
		return
	volatile_risk_item_ids = next_risk_item_ids
	volatile_risk_changed.emit(volatile_risk_item_ids.duplicate())


func _is_risky_item(item_id: StringName, item_data) -> bool:
	var risk_level: int = item_data.risk_level
	if risk_level >= InventoryRiskLevel.MEDIUM:
		return true

	var element_data := ElementDatabase.get_element(item_id)
	if element_data.is_empty():
		return false
	if String(element_data.get(&"category", "")).to_lower() != "volatile":
		return false
	return risk_level >= InventoryRiskLevel.LOW


func _sync_active_item_signal(previous_active_item: StringName) -> void:
	var next_active_item := _get_active_item_id()
	if next_active_item == previous_active_item:
		return
	held_item_changed.emit(next_active_item)


func _mark_game_dirty() -> void:
	if has_node("/root/GameManager"):
		GameManager.mark_dirty()


func _on_weather_tick(state: int, delta: float) -> void:
	if delta <= 0.0 or not items.has(LITHIUM_ITEM_ID):
		return

	if state == WeatherSystem.WeatherState.RAIN:
		if _is_player_exposed_to_rain():
			_adjust_item_purity(LITHIUM_ITEM_ID, -LITHIUM_RAIN_PURITY_LOSS_PER_SECOND * delta)
	elif state == WeatherSystem.WeatherState.ELECTRICAL_STORM:
		charge_lithium(LITHIUM_STORM_CHARGE_GAIN_PER_SECOND * delta)


func _on_heat_event(source_node: Node, radius: float, intensity: float) -> void:
	if source_node == null or not is_instance_valid(source_node):
		return
	if not source_node.is_in_group(&"heat_source"):
		return
	if radius <= 0.0 or intensity <= 0.0:
		_heat_sources.erase(source_node.get_instance_id())
		return
	_heat_sources[source_node.get_instance_id()] = {
		&"source": source_node,
		&"radius": radius,
		&"intensity": intensity,
		&"expires_at_msec": Time.get_ticks_msec() + int(HEAT_SOURCE_TTL_SECONDS * 1000.0),
	}


func _adjust_item_purity(item_id: StringName, amount: float) -> float:
	if amount == 0.0 or not items.has(item_id):
		return 0.0

	var slot_index := _find_slot_for_item(item_id)
	if slot_index == -1:
		return 0.0

	var slot := slots[slot_index]
	var current_purity := clampf(float(slot.get("purity", DEFAULT_ITEM_PURITY)), 0.0, 1.0)
	var next_purity := clampf(current_purity + amount, 0.0, 1.0)
	if is_equal_approx(current_purity, next_purity):
		return next_purity

	slot["purity"] = next_purity
	slots[slot_index] = slot

	var stored_item = _get_stored_item(item_id)
	stored_item.purity = next_purity
	items[item_id] = stored_item

	_post_metadata_mutation(_get_active_item_id())
	inventory_changed.emit(slot_index)
	purity_changed.emit(slot_index, next_purity)
	return next_purity


func _is_player_exposed_to_rain() -> bool:
	var player := GameManager.get_player()
	if player == null:
		return true
	if BaseThreatDirector != null and BaseThreatDirector.has_method("is_rain_exposed_at"):
		return bool(BaseThreatDirector.is_rain_exposed_at(player.global_position))
	if WeatherSystem != null and WeatherSystem.has_method("get_shelter_at"):
		return not bool(WeatherSystem.get_shelter_at(player.global_position))
	return true


func _cleanup_heat_sources() -> void:
	if _heat_sources.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	var expired_ids: Array[int] = []
	for source_id: int in _heat_sources.keys():
		var source_state: Dictionary = _heat_sources[source_id]
		var source_node := source_state.get(&"source", null) as Node
		if source_node == null or not is_instance_valid(source_node):
			expired_ids.append(source_id)
			continue
		if now_msec > int(source_state.get(&"expires_at_msec", 0)):
			expired_ids.append(source_id)
	for source_id: int in expired_ids:
		_heat_sources.erase(source_id)


func _update_sulfur_heat_risk() -> void:
	if not items.has(SULFUR_ITEM_ID):
		_set_sulfur_heat_risk_active(false)
		return

	var player := _get_player()
	if player == null:
		_set_sulfur_heat_risk_active(false)
		return

	for source_state: Dictionary in _heat_sources.values():
		var source_node := source_state.get(&"source", null) as Node2D
		if source_node == null or not is_instance_valid(source_node):
			continue
		var radius := maxf(float(source_state.get(&"radius", 0.0)), 0.0)
		if radius <= 0.0:
			continue
		if player.global_position.distance_to(source_node.global_position) <= radius:
			_set_sulfur_heat_risk_active(true)
			return

	_set_sulfur_heat_risk_active(false)


func _set_sulfur_heat_risk_active(active: bool) -> void:
	if _sulfur_heat_risk_active == active:
		return
	_sulfur_heat_risk_active = active
	if CarrierRiskSystem != null and CarrierRiskSystem.has_method("set_external_trigger"):
		CarrierRiskSystem.set_external_trigger(
			SULFUR_ITEM_ID,
			active,
			SULFUR_HEAT_REASON
		)


func _get_player() -> Node2D:
	return GameManager.get_player()


func _get_stored_item(item_id: StringName):
	if not items.has(item_id):
		return null
	return items[item_id]


func _variant_to_dict(item_data) -> Dictionary:
	if item_data is Dictionary:
		return (item_data as Dictionary).duplicate(true)
	if item_data is Object and item_data.has_method("to_dict") and item_data.has_method("duplicate_item"):
		return item_data.to_dict()
	return {}
