extends Node

const GameplayData = preload("res://scripts/GameplayData.gd")
const FurnacePredictionScript = preload("res://scripts/FurnacePrediction.gd")

const SAVE_STATE_VERSION := 2
const CHECKSUM_ALGORITHM := "sha256"
const CHECKSUM_SCOPE := "envelope_without_integrity"
const DEFAULT_MAX_PLAYER_HEALTH := 100
const MAX_INVENTORY_SLOTS := 5

var placed_stations: Array[Dictionary] = []
var walls: Array[Dictionary] = []
var storage: Array[Dictionary] = []
var chest_inventories: Dictionary = {}
var active_trees: Array[Dictionary] = []
var pending_tree_respawns: Array[Dictionary] = []

var world_seed: String = ""
var biomes_unlocked: Array = []
var explored_tiles: Array = []
var player_position := Vector2.ZERO
var player_health := 100.0
var player_status_effects: Array[StringName] = []
var player_inventory: Array[Dictionary] = []
var active_path: String = ""
var player_active_slot_index: int = 0
var defense_grid_charge: float = 0.0
var discoveries: Array[StringName] = []
var scanner_tier: int = 0
var _validation_errors: Array[String] = []


func _ready() -> void:
	EventBus.register_service(EventBus.SERVICE_WORLD_SAVE_DATA, self)


func _exit_tree() -> void:
	EventBus.unregister_service(EventBus.SERVICE_WORLD_SAVE_DATA, self)


func clear_placed_objects() -> void:
	placed_stations.clear()
	walls.clear()
	storage.clear()
	chest_inventories.clear()


func clear_tree_state() -> void:
	active_trees.clear()
	pending_tree_respawns.clear()

func add_placed_station(entry: Dictionary) -> void:
	placed_stations.append(entry.duplicate(true))

func add_wall(entry: Dictionary) -> void:
	walls.append(entry.duplicate(true))

func add_storage(entry: Dictionary) -> void:
	storage.append(entry.duplicate(true))


func sync_runtime_state() -> void:
	_sync_world_state()
	_sync_player_state()
	_sync_base_state()
	_sync_resource_state()
	_sync_discoveries()
	_sync_progression_state()
	_store_current_scene_state()


func capture_runtime_state() -> Dictionary:
	sync_runtime_state()
	return serialize()


func restore_runtime_state(data: Dictionary) -> void:
	deserialize(data)


func normalize_save_envelope(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	return _migrate_save_data(data)


func encode_storage_value(value: Variant) -> Variant:
	return _variant_to_json_value(value)


func decode_storage_value(value: Variant) -> Variant:
	return _json_value_to_variant(value)


func stringify_save_data(save_data: Dictionary, indent: String = "") -> String:
	return JSON.stringify(encode_storage_value(save_data), indent)


func build_restore_payload(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var normalized_data := normalize_save_envelope(data)
	if normalized_data.is_empty():
		return {}
	return _normalize_restore_payload(normalized_data)


func validate(data: Dictionary) -> bool:
	_validation_errors.clear()
	if data.is_empty():
		_add_validation_error("Save payload is empty.")
		return false

	var normalized_data := _migrate_save_data(data)
	var restore_data := _normalize_restore_payload(normalized_data)
	var player_value: Variant = restore_data.get("player", {})
	if player_value is Dictionary:
		_validate_player_state(player_value as Dictionary)
	elif restore_data.has("player"):
		_add_validation_error("Player state must be a dictionary.")

	var game_manager_value: Variant = restore_data.get("game_manager", {})
	if game_manager_value is Dictionary:
		_validate_game_time(game_manager_value as Dictionary, restore_data.get("metadata", {}) as Dictionary)
	elif restore_data.has("game_manager"):
		_add_validation_error("GameManager state must be a dictionary.")

	return _validation_errors.is_empty()


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _validate_player_state(player_data: Dictionary) -> void:
	if player_data.has("health"):
		var maximum_health := _get_validation_max_health()
		_validate_number_in_range(player_data.get("health"), 0.0, float(maximum_health), "Player health")

	if player_data.has("active_slot_index"):
		var active_slot_value: Variant = player_data.get("active_slot_index")
		if not _is_number(active_slot_value) or int(active_slot_value) != float(active_slot_value) \
			or int(active_slot_value) < 0 or int(active_slot_value) >= MAX_INVENTORY_SLOTS:
			_add_validation_error("Player active slot index is outside the inventory range.")

	if not player_data.has("inventory"):
		return
	var inventory_value: Variant = player_data.get("inventory")
	if not (inventory_value is Array):
		_add_validation_error("Player inventory must be an array.")
		return
	if (inventory_value as Array).size() > MAX_INVENTORY_SLOTS:
		_add_validation_error("Player inventory exceeds the available slot count.")
	for slot_index in range((inventory_value as Array).size()):
		var item_value: Variant = (inventory_value as Array)[slot_index]
		if not (item_value is Dictionary):
			_add_validation_error("Inventory slot %d must be a dictionary." % slot_index)
			continue
		var item_data := item_value as Dictionary
		if item_data.is_empty():
			continue
		_validate_inventory_item(item_data, slot_index)


func _validate_inventory_item(item_data: Dictionary, slot_index: int) -> void:
	var raw_id: Variant = item_data.get("id", item_data.get("item_id", ""))
	var item_id := StringName(str(raw_id))
	if item_id.is_empty():
		_add_validation_error("Inventory slot %d has no item ID." % slot_index)
		return
	if item_data.has("id") and item_data.has("item_id") \
		and StringName(str(item_data.get("id"))) != StringName(str(item_data.get("item_id"))):
		_add_validation_error("Inventory slot %d has conflicting item IDs." % slot_index)
		return
	if not _is_valid_inventory_item_id(item_id):
		_add_validation_error("Inventory slot %d references unknown item '%s'." % [slot_index, String(item_id)])
		return
	if item_data.has("quantity"):
		var quantity_value: Variant = item_data.get("quantity")
		if not _is_number(quantity_value) or int(quantity_value) != float(quantity_value) or int(quantity_value) <= 0:
			_add_validation_error("Inventory slot %d has an invalid quantity." % slot_index)


func _validate_game_time(game_manager_data: Dictionary, metadata: Dictionary) -> void:
	var day_value: Variant = game_manager_data.get("current_day", metadata.get("current_day", null))
	if day_value != null:
		if not _is_number(day_value) or int(day_value) != float(day_value) or int(day_value) <= 0:
			_add_validation_error("Current day must be a positive integer.")
	var time_value: Variant = game_manager_data.get("time_of_day", null)
	if time_value != null:
		_validate_number_in_range(time_value, 0.0, 1.0, "Time of day")


func _validate_number_in_range(value: Variant, minimum: float, maximum: float, label: String) -> void:
	if not _is_number(value):
		_add_validation_error("%s must be numeric." % label)
		return
	var numeric_value := float(value)
	if not is_finite(numeric_value) or numeric_value < minimum or numeric_value > maximum:
		_add_validation_error("%s must be between %s and %s." % [label, minimum, maximum])


func _is_valid_inventory_item_id(item_id: StringName) -> bool:
	if GameplayData.elements().has_element(item_id):
		return true
	# Crafted equipment is stored in inventory but is not represented by ElementDatabase.
	return FurnacePredictionScript.TOOL_RECIPE_DEFINITIONS.has(item_id) \
		or item_id == FurnacePredictionScript.STEEL_SWORD_RECIPE_OUTPUT


func _get_validation_max_health() -> int:
	if GameManager != null:
		return maxi(int(GameManager.max_player_health), 1)
	return DEFAULT_MAX_PLAYER_HEALTH


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _add_validation_error(message: String) -> void:
	_validation_errors.append(message)


func get_saved_scene_path(data: Dictionary) -> String:
	if data.is_empty():
		return "res://scenes/World.tscn"
	var normalized_data := normalize_save_envelope(data)
	var metadata := normalized_data.get("metadata", {}) as Dictionary
	return str(metadata.get("current_scene_path", "res://scenes/World.tscn"))


func extract_save_metadata(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var normalized_data := normalize_save_envelope(data)
	return (normalized_data.get("metadata", {}) as Dictionary).duplicate(true)


func restore_pending_travel_state() -> void:
	var world_system := EventBus.get_world_system()
	if world_system == null or not world_system.has_method("consume_pending_restore_state"):
		return
	var restore_state: Dictionary = world_system.consume_pending_restore_state()
	if restore_state.is_empty():
		return
	var travel_context: Dictionary = (restore_state.get("__travel_context", {}) as Dictionary).duplicate(true)
	restore_state.erase("__travel_context")
	deserialize(restore_state)

	if travel_context.is_empty() and world_system.has_method("consume_pending_travel_context"):
		travel_context = world_system.consume_pending_travel_context()
	var should_use_entry_point := bool(travel_context.get(&"use_entry_point", false))
	var should_save_after_restore := not bool(travel_context.get(&"skip_post_restore_save", false))
	var entry_point_id := StringName(travel_context.get(&"entry_point_id", &""))
	if should_use_entry_point and not entry_point_id.is_empty():
		var scene_root := get_parent()
		if scene_root == null:
			scene_root = get_tree().current_scene
		if scene_root != null and scene_root.has_method("move_player_to_travel_entry"):
			scene_root.call("move_player_to_travel_entry", entry_point_id)
	if EventBus.get_research_objectives() != null and EventBus.get_research_objectives().has_method("sync_with_runtime_state"):
		EventBus.get_research_objectives().sync_with_runtime_state()
	if GameManager != null and GameManager.has_method("finish_load_game"):
		GameManager.finish_load_game()
	sync_runtime_state()
	if should_save_after_restore and GameManager != null and GameManager.has_method("request_save"):
		GameManager.call_deferred("request_save", GameManager.SaveTrigger.BASE_ENTRY)


func serialize() -> Dictionary:
	_store_current_scene_state()
	var current_scene_state := _build_scene_restore_state()
	var current_scene_path := _get_current_scene_path()
	var persistence_sections := _capture_persistent_sections()
	var data := {
		"version": SAVE_STATE_VERSION,
		"metadata": _build_save_metadata(current_scene_path),
		"game_manager": (persistence_sections.get("game_manager", {}) as Dictionary).duplicate(true),
		"world_system": (persistence_sections.get("world_system", {}) as Dictionary).duplicate(true),
		"current_scene_state": current_scene_state.duplicate(true),
		"global_systems": (persistence_sections.get("global_systems", {}) as Dictionary).duplicate(true),
	}
	_attach_integrity_checksum(data)
	return data

func deserialize(data: Dictionary) -> void:
	var normalized_data := _migrate_save_data(data)
	var data_version := int(normalized_data.get("version", 0))
	if data_version > SAVE_STATE_VERSION:
		push_warning(
			"World save data version %d is newer than supported version %d. Attempting best-effort restore."
			% [data_version, SAVE_STATE_VERSION]
		)
	data = _normalize_restore_payload(normalized_data)
	var restored_discovery_log := false
	if is_inside_tree():
		var discovery_log = EventBus.get_discovery_log()
		if PersistenceRegistry != null and PersistenceRegistry.has_method("restore_flattened_state"):
			PersistenceRegistry.restore_flattened_state(data)
		if discovery_log != null and data.has("discovery_log"):
			restored_discovery_log = true
			if discovery_log.has_method("get_all_discoveries"):
				discoveries = discovery_log.get_all_discoveries().duplicate(true)

	if data.has("world"):
		var world_data: Dictionary = data["world"]
		world_seed = world_data.get("seed", "")
		biomes_unlocked = world_data.get("biomes_unlocked", [])
		explored_tiles = world_data.get("explored_tiles", [])
		
	if data.has("player"):
		var player_data: Dictionary = data["player"]
		var pos = player_data.get("position", {"x": 0.0, "y": 0.0})
		player_position = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		player_health = float(player_data.get("health", 100.0))
		player_status_effects = _coerce_string_name_array(player_data.get("status_effects", []))
		player_inventory = []
		for raw_item in player_data.get("inventory", []):
			if raw_item is Dictionary:
				player_inventory.append((raw_item as Dictionary).duplicate(true))
			else:
				player_inventory.append({})
		active_path = str(player_data.get("active_path", ""))
		player_active_slot_index = clampi(int(player_data.get("active_slot_index", 0)), 0, 4)
		var restored_inventory: Array[Dictionary] = player_inventory.duplicate(true)
		if is_inside_tree():
			var gm = get_node_or_null("/root/GameManager")
			if is_instance_valid(gm) and gm.get("player") != null:
				var player = gm.player
				player.global_position = player_position
				var restored_health := maxi(int(player_health), 1)
				if player.has_node("HealthSystem"):
					var health_system: Node = player.get_node("HealthSystem")
					if health_system.has_method("restore_state"):
						health_system.restore_state(restored_health, player_status_effects)
					else:
						health_system.current_health = restored_health
				if gm.has_method("restore_player_runtime_state"):
					gm.restore_player_runtime_state(restored_health, player_status_effects)
					
		if is_inside_tree():
			var inv = get_node_or_null("/root/InventoryManager")
			if inv != null:
				if "active_slot_index" in inv:
					inv.active_slot_index = clampi(player_active_slot_index, 0, inv.DEFAULT_SLOT_COUNT - 1)
				if inv.has_method("restore_slots"):
					inv.restore_slots(restored_inventory, false)
				else:
					inv.clear_inventory()
					for i in range(mini(restored_inventory.size(), inv.DEFAULT_SLOT_COUNT)):
						var item_data = restored_inventory[i]
						if not item_data.is_empty():
							var qty = item_data.get("quantity", 1)
							inv.add_item(item_data, qty)
							inv.move_item_to_slot(item_data.get("id", ""), i)
					if inv.has_method("set_active_slot"):
						inv.set_active_slot(player_active_slot_index)
					
	if data.has("base"):
		var base_data: Dictionary = data["base"]
		placed_stations = _coerce_dictionary_array(base_data.get("placed_stations", []))
		walls = _coerce_dictionary_array(base_data.get("walls", []))
		storage = _coerce_dictionary_array(base_data.get("storage", []))
		chest_inventories = base_data.get("chest_inventories", {})
		defense_grid_charge = float(base_data.get("defense_grid_charge", 0.0))
		var base_grid := EventBus.get_base_grid()
		if base_grid != null and base_grid.has_method("restore_charge_level"):
			base_grid.restore_charge_level(defense_grid_charge)
		
		if is_inside_tree():
			var build_sys = EventBus.get_build_system()
			if build_sys != null and build_sys.has_method("import_from_world_save_data"):
				build_sys.import_from_world_save_data(self)
			var storage_manager = EventBus.get_storage_manager()
			if storage_manager != null and storage_manager.has_method("import_from_world_save_data"):
				storage_manager.import_from_world_save_data(self)

	if data.has("resources"):
		var resource_data: Dictionary = data["resources"]
		active_trees = _coerce_dictionary_array(resource_data.get("active_trees", []))
		pending_tree_respawns = _coerce_dictionary_array(resource_data.get("pending_tree_respawns", []))
		if is_inside_tree():
			var current_scene := get_tree().current_scene
			if current_scene != null and current_scene.has_method("import_tree_state"):
				current_scene.call("import_tree_state", active_trees, pending_tree_respawns)
	else:
		clear_tree_state()
				
	if data.has("discoveries") and not restored_discovery_log:
		discoveries = []
		for raw_discovery in data["discoveries"]:
			discoveries.append(StringName(str(raw_discovery)))
		if is_inside_tree():
			var dlog = EventBus.get_discovery_log()
			if dlog != null:
				if dlog.has_method("restore_discoveries"):
					dlog.restore_discoveries(discoveries)
				elif "unlocked_elements" in dlog:
					dlog.unlocked_elements = discoveries.duplicate(true)

	if data.has("progression"):
		var progression_data: Dictionary = data["progression"]
		scanner_tier = int(progression_data.get("scanner_tier", 0))
		if is_inside_tree():
			var gm = get_node_or_null("/root/GameManager")
			if gm != null and gm.has_method("restore_scanner_tier"):
				gm.restore_scanner_tier(scanner_tier)


func _migrate_save_data(data: Dictionary) -> Dictionary:
	if data.is_empty():
		var empty_envelope := _build_empty_envelope()
		_attach_integrity_checksum(empty_envelope)
		return empty_envelope
	if _is_backend_save_envelope(data):
		var integrity_valid := _verify_integrity_checksum(data, false)
		var migrated_envelope := _ensure_envelope_defaults(data.duplicate(true))
		var data_version := int(migrated_envelope.get("version", SAVE_STATE_VERSION))
		if data_version <= 0:
			data_version = 1
		while data_version < SAVE_STATE_VERSION:
			match data_version:
				1:
					data_version = 2
				_:
					data_version = SAVE_STATE_VERSION
		migrated_envelope["version"] = data_version
		var metadata := (migrated_envelope.get("metadata", {}) as Dictionary).duplicate(true)
		if str(metadata.get("migration_status", "")).is_empty():
			metadata["migration_status"] = "current"
		if not integrity_valid and str(metadata.get("migration_status", "")) == "current":
			metadata["migration_status"] = "checksum_repaired"
		migrated_envelope["metadata"] = metadata
		_attach_integrity_checksum(migrated_envelope)
		return migrated_envelope

	var flat_save := data.duplicate(true)
	var flat_version := int(flat_save.get("version", 0))
	var migration_status := "migrated_from_flat_versionless"
	if flat_version > 0:
		migration_status = "migrated_from_flat_v%d" % flat_version
	var migrated_flat := _build_envelope_from_flat_save(flat_save, migration_status)
	_attach_integrity_checksum(migrated_flat)
	return migrated_flat


func _sync_world_state() -> void:
	var world_system := EventBus.get_world_system()
	if world_system == null:
		return
	var current_scene := get_tree().current_scene
	var current_scene_path := str(current_scene.scene_file_path) if current_scene != null else ""
	if world_system.has_method("get_seed_for_scene") and not current_scene_path.is_empty():
		world_seed = str(world_system.get_seed_for_scene(current_scene_path))
	elif world_system.has_method("get_seed"):
		world_seed = str(world_system.get_seed())


func _sync_player_state() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("get_player"):
		var player := gm.get_player() as Node2D
		if player != null:
			player_position = player.global_position
			if player.has_node("HealthSystem"):
				player_health = float(player.get_node("HealthSystem").current_health)
	player_status_effects = GameManager.player_status_effects.duplicate(true)
	var current_scene := get_tree().current_scene
	active_path = str(current_scene.scene_file_path) if current_scene != null else ""

	var inv := get_node_or_null("/root/InventoryManager")
	if inv != null:
		player_active_slot_index = clampi(int(inv.active_slot_index), 0, inv.DEFAULT_SLOT_COUNT - 1)
		player_inventory.clear()
		for i in range(inv.DEFAULT_SLOT_COUNT):
			var item = inv.get_slot_item(i)
			player_inventory.append(item.duplicate(true) if not item.is_empty() else {})


func _sync_base_state() -> void:
	var build_system := EventBus.get_build_system()
	if build_system != null and build_system.has_method("export_to_world_save_data"):
		build_system.export_to_world_save_data(self)
	var base_grid := EventBus.get_base_grid()
	if base_grid != null and base_grid.has_method("get_charge_state"):
		defense_grid_charge = float(base_grid.get_charge_state())


func _sync_resource_state() -> void:
	clear_tree_state()
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("export_tree_state"):
		var tree_state: Dictionary = current_scene.call("export_tree_state")
		for entry in tree_state.get("active_trees", []):
			if entry is Dictionary:
				active_trees.append((entry as Dictionary).duplicate(true))
		for entry in tree_state.get("pending_tree_respawns", []):
			if entry is Dictionary:
				pending_tree_respawns.append((entry as Dictionary).duplicate(true))


func _sync_discoveries() -> void:
	discoveries.clear()
	var dlog := EventBus.get_discovery_log()
	if dlog == null:
		return
	if dlog.has_method("get_all_discoveries"):
		discoveries = dlog.get_all_discoveries().duplicate(true)
	elif "unlocked_elements" in dlog:
		for unlocked in dlog.unlocked_elements:
			discoveries.append(StringName(str(unlocked)))


func _sync_progression_state() -> void:
	scanner_tier = int(GameManager.scanner_tier)


func _store_current_scene_state() -> void:
	if not is_inside_tree():
		return
	var world_system := EventBus.get_world_system()
	if world_system == null or not world_system.has_method("store_scene_state"):
		return
	var current_scene_path := _get_current_scene_path()
	if current_scene_path.is_empty():
		return
	world_system.store_scene_state(current_scene_path, _build_scene_restore_state())


func _get_current_scene_path() -> String:
	if not active_path.is_empty():
		return active_path
	var current_scene := get_tree().current_scene if is_inside_tree() else null
	return str(current_scene.scene_file_path) if current_scene != null else ""


func _build_scene_restore_state() -> Dictionary:
	return {
		"world": {
			"seed": world_seed,
			"biomes_unlocked": biomes_unlocked.duplicate(true),
			"explored_tiles": explored_tiles.duplicate(true),
		},
		"player": {
			"position": {"x": player_position.x, "y": player_position.y},
			"health": player_health,
			"status_effects": player_status_effects.duplicate(true),
			"inventory": player_inventory.duplicate(true),
			"active_path": active_path,
			"active_slot_index": player_active_slot_index,
		},
		"base": {
			"placed_stations": placed_stations.duplicate(true),
			"walls": walls.duplicate(true),
			"storage": storage.duplicate(true),
			"chest_inventories": chest_inventories.duplicate(true),
			"defense_grid_charge": defense_grid_charge,
		},
		"resources": {
			"active_trees": active_trees.duplicate(true),
			"pending_tree_respawns": pending_tree_respawns.duplicate(true),
		},
		"discoveries": discoveries.duplicate(true),
		"progression": {
			"scanner_tier": scanner_tier,
		},
	}


func _build_empty_envelope() -> Dictionary:
	var persistence_sections := _build_empty_persistence_sections()
	return {
		"version": SAVE_STATE_VERSION,
		"metadata": _build_save_metadata(""),
		"game_manager": (persistence_sections.get("game_manager", {}) as Dictionary).duplicate(true),
		"world_system": (persistence_sections.get("world_system", {}) as Dictionary).duplicate(true),
		"current_scene_state": {},
		"global_systems": (persistence_sections.get("global_systems", {}) as Dictionary).duplicate(true),
	}


func _build_save_metadata(current_scene_path: String, migration_status: String = "current", source_metadata: Dictionary = {}) -> Dictionary:
	var metadata := source_metadata.duplicate(true)
	metadata["slot_id"] = int(source_metadata.get("slot_id", int(GameManager.active_save_slot) if GameManager != null else 1))
	metadata["account_id"] = str(source_metadata.get("account_id", ""))
	metadata["saved_at_unix"] = int(source_metadata.get("saved_at_unix", Time.get_unix_time_from_system()))
	metadata["current_day"] = int(source_metadata.get("current_day", int(GameManager.current_day) if GameManager != null else 1))
	metadata["current_scene_path"] = str(source_metadata.get("current_scene_path", current_scene_path))
	metadata["migration_status"] = str(source_metadata.get("migration_status", migration_status))
	if not metadata.has("integrity") or not (metadata.get("integrity", {}) is Dictionary):
		metadata["integrity"] = {}
	return metadata


func _capture_persistent_sections() -> Dictionary:
	if PersistenceRegistry != null and PersistenceRegistry.has_method("capture_persistent_sections"):
		return PersistenceRegistry.capture_persistent_sections()
	return _build_empty_persistence_sections()


func _build_empty_persistence_sections() -> Dictionary:
	if PersistenceRegistry != null and PersistenceRegistry.has_method("build_empty_sections"):
		return PersistenceRegistry.build_empty_sections()
	return {
		"game_manager": {},
		"world_system": {},
		"global_systems": {},
	}


func _build_persistence_sections_from_flat_save(flat_save: Dictionary) -> Dictionary:
	if PersistenceRegistry != null and PersistenceRegistry.has_method("build_sections_from_flat_save"):
		return PersistenceRegistry.build_sections_from_flat_save(flat_save)
	return _build_empty_persistence_sections()


func _build_envelope_from_flat_save(flat_save: Dictionary, migration_status: String) -> Dictionary:
	var current_scene_path := _get_saved_scene_path_from_flat_save(flat_save)
	var source_metadata := (flat_save.get("metadata", {}) as Dictionary).duplicate(true)
	var envelope := _build_empty_envelope()
	envelope["metadata"] = _build_save_metadata(current_scene_path, migration_status, source_metadata)
	var persistence_sections := _build_persistence_sections_from_flat_save(flat_save)
	envelope["game_manager"] = (persistence_sections.get("game_manager", {}) as Dictionary).duplicate(true)
	var world_system_state := persistence_sections.get("world_system", {}) as Dictionary
	if world_system_state.is_empty():
		world_system_state = _build_world_system_payload_from_flat_save(flat_save)
	envelope["world_system"] = world_system_state.duplicate(true)
	envelope["current_scene_state"] = _build_scene_restore_state_from_save(flat_save)
	envelope["global_systems"] = (persistence_sections.get("global_systems", {}) as Dictionary).duplicate(true)
	envelope["current_scene_state"] = _extract_current_scene_state_from_envelope(envelope)
	return envelope


func _ensure_envelope_defaults(save_data: Dictionary) -> Dictionary:
	var envelope := save_data.duplicate(true)
	if not envelope.has("version"):
		envelope["version"] = SAVE_STATE_VERSION
	var metadata := (envelope.get("metadata", {}) as Dictionary).duplicate(true)
	var current_scene_path := str(metadata.get("current_scene_path", ""))
	if current_scene_path.is_empty():
		current_scene_path = _get_saved_scene_path_from_flat_save(envelope)
	envelope["metadata"] = _build_save_metadata(current_scene_path, "current", metadata)
	if not envelope.has("game_manager") or not (envelope.get("game_manager", {}) is Dictionary):
		envelope["game_manager"] = {}
	if not envelope.has("world_system") or not (envelope.get("world_system", {}) is Dictionary):
		envelope["world_system"] = {}
	if not envelope.has("current_scene_state") or not (envelope.get("current_scene_state", {}) is Dictionary):
		envelope["current_scene_state"] = {}
	var default_persistence_sections := _build_empty_persistence_sections()
	if not envelope.has("global_systems") or not (envelope.get("global_systems", {}) is Dictionary):
		envelope["global_systems"] = (default_persistence_sections.get("global_systems", {}) as Dictionary).duplicate(true)
	else:
		var global_systems := (default_persistence_sections.get("global_systems", {}) as Dictionary).duplicate(true)
		var existing_global_systems := envelope.get("global_systems", {}) as Dictionary
		for key in global_systems.keys():
			if existing_global_systems.has(key) and existing_global_systems[key] is Dictionary:
				global_systems[key] = (existing_global_systems[key] as Dictionary).duplicate(true)
		envelope["global_systems"] = global_systems
	envelope["current_scene_state"] = _extract_current_scene_state_from_envelope(envelope)
	return envelope


func _normalize_restore_payload(save_data: Dictionary) -> Dictionary:
	if not _is_backend_save_envelope(save_data):
		return save_data.duplicate(true)
	var current_scene_state := _extract_current_scene_state_from_envelope(save_data)
	var restore_state := _build_scene_restore_state_from_save(current_scene_state)
	restore_state["version"] = int(save_data.get("version", SAVE_STATE_VERSION))
	restore_state["metadata"] = (save_data.get("metadata", {}) as Dictionary).duplicate(true)
	restore_state["game_manager"] = (save_data.get("game_manager", {}) as Dictionary).duplicate(true)
	restore_state["world_system"] = (save_data.get("world_system", {}) as Dictionary).duplicate(true)
	var global_systems := save_data.get("global_systems", {}) as Dictionary
	for key in global_systems.keys():
		if global_systems[key] is Dictionary:
			restore_state[key] = (global_systems[key] as Dictionary).duplicate(true)
	return restore_state


func _extract_current_scene_state_from_envelope(save_data: Dictionary) -> Dictionary:
	var current_scene_state := (save_data.get("current_scene_state", {}) as Dictionary).duplicate(true)
	if not current_scene_state.is_empty():
		return current_scene_state
	var metadata := save_data.get("metadata", {}) as Dictionary
	var current_scene_path := str(metadata.get("current_scene_path", ""))
	var world_system_data := save_data.get("world_system", {}) as Dictionary
	var scene_state_by_path := world_system_data.get("scene_state_by_path", {}) as Dictionary
	if not current_scene_path.is_empty():
		return (scene_state_by_path.get(current_scene_path, {}) as Dictionary).duplicate(true)
	for scene_state in scene_state_by_path.values():
		if scene_state is Dictionary:
			return (scene_state as Dictionary).duplicate(true)
	return {}


func _build_world_system_payload_from_flat_save(save_data: Dictionary) -> Dictionary:
	var current_scene_path := _get_saved_scene_path_from_flat_save(save_data)
	var world_seed := str((save_data.get("world", {}) as Dictionary).get("seed", ""))
	var current_seed := int(world_seed) if not world_seed.is_empty() else 0
	var scene_seeds := {}
	var scene_state_by_path := {}
	if not current_scene_path.is_empty():
		if current_seed != 0:
			scene_seeds[current_scene_path] = current_seed
		scene_state_by_path[current_scene_path] = _build_scene_restore_state_from_save(save_data)
	return {
		"current_seed": current_seed,
		"scene_seeds": scene_seeds,
		"scene_state_by_path": scene_state_by_path,
	}


func _build_scene_restore_state_from_save(save_data: Dictionary) -> Dictionary:
	var scene_state := {}
	for key in ["world", "player", "base", "resources", "progression"]:
		var value: Variant = save_data.get(key, {})
		if value is Dictionary and not (value as Dictionary).is_empty():
			scene_state[key] = (value as Dictionary).duplicate(true)
	var discoveries_value: Variant = save_data.get("discoveries", [])
	if discoveries_value is Array and not (discoveries_value as Array).is_empty():
		scene_state["discoveries"] = (discoveries_value as Array).duplicate(true)
	return scene_state


func _get_saved_scene_path_from_flat_save(save_data: Dictionary) -> String:
	var metadata := save_data.get("metadata", {}) as Dictionary
	var current_scene_path := str(metadata.get("current_scene_path", ""))
	if current_scene_path.is_empty():
		var player_state := save_data.get("player", {}) as Dictionary
		current_scene_path = str(player_state.get("active_path", ""))
	if current_scene_path.is_empty():
		var game_manager_state := save_data.get("game_manager", {}) as Dictionary
		current_scene_path = str(game_manager_state.get("current_scene_path", ""))
	if current_scene_path.is_empty():
		return "res://scenes/World.tscn"
	return current_scene_path


func _is_backend_save_envelope(save_data: Dictionary) -> bool:
	return save_data.has("current_scene_state") or save_data.has("global_systems")


func _attach_integrity_checksum(save_data: Dictionary) -> void:
	var metadata := (save_data.get("metadata", {}) as Dictionary).duplicate(true)
	var integrity := {
		"algorithm": CHECKSUM_ALGORITHM,
		"checksum_scope": CHECKSUM_SCOPE,
	}
	metadata["integrity"] = integrity
	save_data["metadata"] = metadata
	integrity["checksum"] = _compute_integrity_checksum(save_data)
	metadata["integrity"] = integrity
	save_data["metadata"] = metadata


func _verify_integrity_checksum(save_data: Dictionary, emit_warning: bool = true) -> bool:
	var metadata := save_data.get("metadata", {}) as Dictionary
	var integrity := metadata.get("integrity", {}) as Dictionary
	if integrity.is_empty():
		return true
	var expected_checksum := str(integrity.get("checksum", ""))
	if expected_checksum.is_empty():
		return true
	var actual_checksum := _compute_integrity_checksum(save_data)
	if expected_checksum == actual_checksum:
		return true
	if emit_warning:
		push_warning("Save payload checksum mismatch. Expected %s, computed %s." % [expected_checksum, actual_checksum])
	return false


func _compute_integrity_checksum(save_data: Dictionary) -> String:
	var normalized_payload := save_data.duplicate(true)
	var metadata := (normalized_payload.get("metadata", {}) as Dictionary).duplicate(true)
	var integrity := (metadata.get("integrity", {}) as Dictionary).duplicate(true)
	integrity.erase("checksum")
	integrity.erase("verified")
	metadata["integrity"] = integrity
	normalized_payload["metadata"] = metadata
	var canonical_payload := JSON.stringify(_variant_to_json_value(normalized_payload))
	return canonical_payload.sha256_text()


func _variant_to_json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return {
				"__type": "StringName",
				"value": str(value),
			}
		TYPE_DICTIONARY:
			var json_dict := {}
			var dictionary_value := value as Dictionary
			var sorted_keys: Array[String] = []
			var key_lookup := {}
			for raw_key in dictionary_value.keys():
				var sort_key := str(raw_key)
				sorted_keys.append(sort_key)
				key_lookup[sort_key] = raw_key
			sorted_keys.sort()
			for sort_key in sorted_keys:
				var raw_lookup_key: Variant = key_lookup.get(sort_key, sort_key)
				json_dict[sort_key] = _variant_to_json_value(dictionary_value[raw_lookup_key])
			return json_dict
		TYPE_ARRAY:
			var json_array: Array = []
			for item in (value as Array):
				json_array.append(_variant_to_json_value(item))
			return json_array
		TYPE_VECTOR2:
			var vector2 := value as Vector2
			return {
				"__type": "Vector2",
				"x": vector2.x,
				"y": vector2.y,
			}
		TYPE_VECTOR2I:
			var vector2i := value as Vector2i
			return {
				"__type": "Vector2i",
				"x": vector2i.x,
				"y": vector2i.y,
			}
		_:
			return {
				"__type": "VariantString",
				"value": var_to_str(value),
			}


func _json_value_to_variant(value: Variant) -> Variant:
	if value is Array:
		var restored_array: Array = []
		for item in value:
			restored_array.append(_json_value_to_variant(item))
		return restored_array
	if not (value is Dictionary):
		return value
	var value_dict := value as Dictionary
	var type_name := str(value_dict.get("__type", ""))
	match type_name:
		"StringName":
			return StringName(str(value_dict.get("value", "")))
		"Vector2":
			return Vector2(
				float(value_dict.get("x", 0.0)),
				float(value_dict.get("y", 0.0))
			)
		"Vector2i":
			return Vector2i(
				int(value_dict.get("x", 0)),
				int(value_dict.get("y", 0))
			)
		"VariantString":
			return str_to_var(str(value_dict.get("value", "")))
		_:
			var restored_dict := {}
			for raw_key in value_dict.keys():
				restored_dict[raw_key] = _json_value_to_variant(value_dict[raw_key])
			return restored_dict


func _coerce_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (raw_value is Array):
		return result
	for entry in raw_value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func _coerce_string_name_array(raw_value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not (raw_value is Array):
		return result
	for entry in raw_value:
		result.append(StringName(str(entry)))
	return result
