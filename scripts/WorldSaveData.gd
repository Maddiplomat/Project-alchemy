extends Node

const SAVE_STATE_VERSION := 2
const CHECKSUM_ALGORITHM := "sha256"
const CHECKSUM_SCOPE := "envelope_without_integrity"

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


func restore_pending_travel_state() -> void:
	var world_system := get_node_or_null("/root/WorldSystem")
	if world_system == null or not world_system.has_method("consume_pending_restore_state"):
		return
	var restore_state: Dictionary = world_system.consume_pending_restore_state()
	if restore_state.is_empty():
		return
	deserialize(restore_state)

	var travel_context: Dictionary = {}
	if world_system.has_method("consume_pending_travel_context"):
		travel_context = world_system.consume_pending_travel_context()
	var should_use_entry_point := bool(travel_context.get(&"use_entry_point", false))
	var should_save_after_restore := not bool(travel_context.get(&"skip_post_restore_save", false))
	var entry_point_id := StringName(travel_context.get(&"entry_point_id", &""))
	if should_use_entry_point and not entry_point_id.is_empty():
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.has_method("move_player_to_travel_entry"):
			current_scene.call("move_player_to_travel_entry", entry_point_id)
	if ResearchObjectives != null and ResearchObjectives.has_method("sync_with_runtime_state"):
		ResearchObjectives.sync_with_runtime_state()
	if GameManager != null and GameManager.has_method("finish_load_game"):
		GameManager.finish_load_game()
	sync_runtime_state()
	if should_save_after_restore and GameManager != null and GameManager.has_method("request_save"):
		GameManager.call_deferred("request_save", GameManager.SaveTrigger.BASE_ENTRY)


func serialize() -> Dictionary:
	_store_current_scene_state()
	var current_scene_state := _build_scene_restore_state()
	var current_scene_path := _get_current_scene_path()
	var data := {
		"version": SAVE_STATE_VERSION,
		"metadata": _build_save_metadata(current_scene_path),
		"game_manager": {},
		"world_system": {},
		"current_scene_state": current_scene_state.duplicate(true),
		"global_systems": _build_global_system_state(),
	}
	if GameManager != null and GameManager.has_method("capture_persistent_state"):
		data["game_manager"] = GameManager.capture_persistent_state()
	var world_system := get_node_or_null("/root/WorldSystem") if is_inside_tree() else null
	if world_system != null and world_system.has_method("capture_persistent_state"):
		data["world_system"] = world_system.capture_persistent_state()
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
		var world_system = get_node_or_null("/root/WorldSystem")
		if world_system != null and data.has("world_system") and world_system.has_method("restore_persistent_state"):
			world_system.restore_persistent_state((data.get("world_system", {}) as Dictionary).duplicate(true))
		var gm = get_node_or_null("/root/GameManager")
		if gm != null and data.has("game_manager") and gm.has_method("restore_persistent_state"):
			gm.restore_persistent_state((data.get("game_manager", {}) as Dictionary).duplicate(true))
		if ElementDatabase != null and data.has("element_database") and ElementDatabase.has_method("restore_persistent_state"):
			ElementDatabase.restore_persistent_state((data.get("element_database", {}) as Dictionary).duplicate(true))
		var discovery_log = get_node_or_null("/root/DiscoveryLog")
		if discovery_log != null and data.has("discovery_log") and discovery_log.has_method("restore_persistent_state"):
			discovery_log.restore_persistent_state((data.get("discovery_log", {}) as Dictionary).duplicate(true))
			restored_discovery_log = true
			if discovery_log.has_method("get_all_discoveries"):
				discoveries = discovery_log.get_all_discoveries().duplicate(true)
		var research_objectives = get_node_or_null("/root/ResearchObjectives")
		if research_objectives != null and data.has("research_objectives") and research_objectives.has_method("restore_persistent_state"):
			research_objectives.restore_persistent_state((data.get("research_objectives", {}) as Dictionary).duplicate(true))
		var power_switchboard := EventBus.get_power_switchboard()
		if power_switchboard != null and data.has("power_switchboard") and power_switchboard.has_method("restore_persistent_state"):
			power_switchboard.restore_persistent_state((data.get("power_switchboard", {}) as Dictionary).duplicate(true))
		if WeatherSystem != null and data.has("weather_system") and WeatherSystem.has_method("restore_persistent_state"):
			WeatherSystem.restore_persistent_state((data.get("weather_system", {}) as Dictionary).duplicate(true))
		var cold_system := EventBus.get_cold_system()
		if cold_system != null and data.has("cold_system") and cold_system.has_method("restore_persistent_state"):
			cold_system.restore_persistent_state((data.get("cold_system", {}) as Dictionary).duplicate(true))

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
			var build_sys = get_node_or_null("/root/BuildSystem")
			if build_sys != null and build_sys.has_method("import_from_world_save_data"):
				build_sys.import_from_world_save_data(self)
			var storage_manager = get_node_or_null("/root/StorageManager")
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
			var dlog = get_node_or_null("/root/DiscoveryLog")
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
		_verify_integrity_checksum(data)
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
	var world_system := get_node_or_null("/root/WorldSystem")
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
	var build_system := get_node_or_null("/root/BuildSystem")
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
		active_trees = (tree_state.get("active_trees", []) as Array).duplicate(true)
		pending_tree_respawns = (tree_state.get("pending_tree_respawns", []) as Array).duplicate(true)


func _sync_discoveries() -> void:
	discoveries.clear()
	var dlog := get_node_or_null("/root/DiscoveryLog")
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
	var world_system := get_node_or_null("/root/WorldSystem")
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
	return {
		"version": SAVE_STATE_VERSION,
		"metadata": _build_save_metadata(""),
		"game_manager": {},
		"world_system": {},
		"current_scene_state": {},
		"global_systems": _build_global_system_state(false),
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


func _build_global_system_state(capture_runtime: bool = true) -> Dictionary:
	var global_systems := {
		"element_database": {},
		"discovery_log": {},
		"research_objectives": {},
		"power_switchboard": {},
		"weather_system": {},
		"cold_system": {},
	}
	if not capture_runtime:
		return global_systems
	if ElementDatabase != null and ElementDatabase.has_method("capture_persistent_state"):
		global_systems["element_database"] = ElementDatabase.capture_persistent_state()
	var discovery_log := get_node_or_null("/root/DiscoveryLog") if is_inside_tree() else null
	if discovery_log != null and discovery_log.has_method("capture_persistent_state"):
		global_systems["discovery_log"] = discovery_log.capture_persistent_state()
	var research_objectives := get_node_or_null("/root/ResearchObjectives") if is_inside_tree() else null
	if research_objectives != null and research_objectives.has_method("capture_persistent_state"):
		global_systems["research_objectives"] = research_objectives.capture_persistent_state()
	var power_switchboard := EventBus.get_power_switchboard() if is_inside_tree() else null
	if power_switchboard != null and power_switchboard.has_method("capture_persistent_state"):
		global_systems["power_switchboard"] = power_switchboard.capture_persistent_state()
	if WeatherSystem != null and WeatherSystem.has_method("capture_persistent_state"):
		global_systems["weather_system"] = WeatherSystem.capture_persistent_state()
	var cold_system := EventBus.get_cold_system() if is_inside_tree() else null
	if cold_system != null and cold_system.has_method("capture_persistent_state"):
		global_systems["cold_system"] = cold_system.capture_persistent_state()
	return global_systems


func _build_envelope_from_flat_save(flat_save: Dictionary, migration_status: String) -> Dictionary:
	var current_scene_path := _get_saved_scene_path_from_flat_save(flat_save)
	var source_metadata := (flat_save.get("metadata", {}) as Dictionary).duplicate(true)
	var envelope := _build_empty_envelope()
	envelope["metadata"] = _build_save_metadata(current_scene_path, migration_status, source_metadata)
	var game_manager_state := flat_save.get("game_manager", {}) as Dictionary
	if not game_manager_state.is_empty():
		envelope["game_manager"] = game_manager_state.duplicate(true)
	var world_system_state := flat_save.get("world_system", {}) as Dictionary
	if world_system_state.is_empty():
		world_system_state = _build_world_system_payload_from_flat_save(flat_save)
	envelope["world_system"] = world_system_state.duplicate(true)
	envelope["current_scene_state"] = _build_scene_restore_state_from_save(flat_save)
	envelope["global_systems"] = {
		"element_database": (flat_save.get("element_database", {}) as Dictionary).duplicate(true),
		"discovery_log": (flat_save.get("discovery_log", {}) as Dictionary).duplicate(true),
		"research_objectives": (flat_save.get("research_objectives", {}) as Dictionary).duplicate(true),
		"power_switchboard": (flat_save.get("power_switchboard", {}) as Dictionary).duplicate(true),
		"weather_system": (flat_save.get("weather_system", {}) as Dictionary).duplicate(true),
		"cold_system": (flat_save.get("cold_system", {}) as Dictionary).duplicate(true),
	}
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
	if not envelope.has("global_systems") or not (envelope.get("global_systems", {}) is Dictionary):
		envelope["global_systems"] = _build_global_system_state(false)
	else:
		var global_systems := _build_global_system_state(false)
		var existing_global_systems := envelope.get("global_systems", {}) as Dictionary
		for key in global_systems.keys():
			if existing_global_systems.has(key) and existing_global_systems[key] is Dictionary:
				global_systems[key] = (existing_global_systems[key] as Dictionary).duplicate(true)
		envelope["global_systems"] = global_systems
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


func _verify_integrity_checksum(save_data: Dictionary) -> bool:
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
