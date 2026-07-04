extends Node

const WorldSaveDataScript = preload("res://scripts/WorldSaveData.gd")
const PowerSwitchboardScript = preload("res://scripts/PowerSwitchboard.gd")
const DoorScene = preload("res://scenes/Door.tscn")
const CampfireScene = preload("res://scenes/Campfire.tscn")

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const SODIUM_SHOALS_SCENE_PATH := "res://scenes/SodiumShoals.tscn"

var _failures := 0
var _world_save_data: Node = null
var _power_switchboard: Node = null
var _switchboard_restore_signals := 0


func _ready() -> void:
	await _run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	WorldSystem.clear_persistent_state()
	_power_switchboard = PowerSwitchboardScript.new()
	_world_save_data = WorldSaveDataScript.new()
	add_child(_power_switchboard)
	add_child(_world_save_data)
	await get_tree().process_frame

	_run_world_snapshot_regression()
	await _run_build_restore_regression()

	_world_save_data.queue_free()
	_power_switchboard.queue_free()
	await get_tree().process_frame

	if _failures == 0:
		print("SavePersistenceRegressionTest passed.")


func _run_world_snapshot_regression() -> void:
	var world_scene_state := _build_scene_state(
		"10101",
		WORLD_SCENE_PATH,
		Vector2(64.0, 96.0),
		[
			{
				"scene_path": "res://scenes/Campfire.tscn",
				"placed_at": Vector2i(10, 12),
				"is_lit": false,
				"burn_time_remaining": 180.0,
			},
		],
		[
			{
				"scene_path": "res://scenes/Door.tscn",
				"placed_at": Vector2i(9, 12),
				"is_open": true,
			},
		]
	)
	var sodium_scene_state := _build_scene_state(
		"20202",
		SODIUM_SHOALS_SCENE_PATH,
		Vector2(320.0, 208.0),
		[
			{
				"scene_path": "res://scenes/Campfire.tscn",
				"placed_at": Vector2i(4, 7),
				"is_lit": true,
				"burn_time_remaining": 420.0,
			},
		],
		[
			{
				"scene_path": "res://scenes/Door.tscn",
				"placed_at": Vector2i(5, 7),
				"is_open": false,
			},
		]
	)

	WorldSystem.store_scene_state(WORLD_SCENE_PATH, world_scene_state)
	_power_switchboard.set_consumer_enabled(_power_switchboard.CONSUMER_TRAP_NETWORK, false)
	_power_switchboard.set_consumer_enabled(_power_switchboard.CONSUMER_FURNACE_BOOST, false)
	_apply_scene_state_to_world_save_data(_world_save_data, sodium_scene_state)

	var serialized: Dictionary = _world_save_data.serialize()
	_assert(serialized.has("current_scene_state"), "Expected new saves to include current_scene_state in the top-level envelope.")
	_assert(serialized.has("global_systems"), "Expected new saves to include global_systems in the top-level envelope.")
	var world_system_data := serialized.get("world_system", {}) as Dictionary
	var scene_state_by_path := world_system_data.get("scene_state_by_path", {}) as Dictionary
	var current_scene_state := serialized.get("current_scene_state", {}) as Dictionary
	_assert(scene_state_by_path.has(WORLD_SCENE_PATH), "Expected save payload to include the World snapshot.")
	_assert(scene_state_by_path.has(SODIUM_SHOALS_SCENE_PATH), "Expected save payload to include the active Sodium Shoals snapshot.")
	_assert(
		_scene_states_match(world_scene_state, scene_state_by_path.get(WORLD_SCENE_PATH, {})),
		"Expected World snapshot to survive serialization."
	)
	_assert(
		_scene_states_match(sodium_scene_state, scene_state_by_path.get(SODIUM_SHOALS_SCENE_PATH, {})),
		"Expected Sodium Shoals snapshot to survive serialization."
	)
	_assert(
		_scene_states_match(sodium_scene_state, current_scene_state),
		"Expected current_scene_state to mirror the active Sodium Shoals snapshot."
	)

	var global_systems := serialized.get("global_systems", {}) as Dictionary
	var switchboard_state := global_systems.get("power_switchboard", {}) as Dictionary
	var consumer_enabled := switchboard_state.get("consumer_enabled", {}) as Dictionary
	_assert(
		not bool(consumer_enabled.get("trap_network", true)),
		"Expected serialized switchboard state to preserve the trap network toggle."
	)
	_assert(
		not bool(consumer_enabled.get("furnace_boost", true)),
		"Expected serialized switchboard state to preserve the furnace boost toggle."
	)

	var extracted_full := GameManager._extract_world_save_data(serialized)
	_assert(not extracted_full.is_empty(), "Expected full-save payload extraction to succeed.")
	_assert(extracted_full.has("world_system"), "Expected extracted full-save payload to retain world_system state.")
	_assert(extracted_full.has("power_switchboard"), "Expected extracted full-save payload to retain switchboard state.")
	_assert(
		_scene_states_match(sodium_scene_state, _extract_scene_state_from_restore_payload(extracted_full)),
		"Expected envelope extraction to recover the active current_scene_state."
	)

	var legacy_payload: Dictionary = serialized.duplicate(true)
	legacy_payload["version"] = 1
	legacy_payload.erase("world_system")
	legacy_payload.erase("current_scene_state")
	legacy_payload.erase("global_systems")
	legacy_payload["world"] = (sodium_scene_state.get("world", {}) as Dictionary).duplicate(true)
	legacy_payload["player"] = (sodium_scene_state.get("player", {}) as Dictionary).duplicate(true)
	legacy_payload["base"] = (sodium_scene_state.get("base", {}) as Dictionary).duplicate(true)
	legacy_payload["resources"] = (sodium_scene_state.get("resources", {}) as Dictionary).duplicate(true)
	legacy_payload["discoveries"] = (sodium_scene_state.get("discoveries", []) as Array).duplicate(true)
	legacy_payload["progression"] = (sodium_scene_state.get("progression", {}) as Dictionary).duplicate(true)
	var extracted_legacy := GameManager._extract_world_save_data(legacy_payload)
	var legacy_world_system := extracted_legacy.get("world_system", {}) as Dictionary
	var legacy_scene_state_by_path := legacy_world_system.get("scene_state_by_path", {}) as Dictionary
	_assert(not extracted_legacy.is_empty(), "Expected flat-save payload extraction to succeed.")
	_assert(
		_scene_states_match(sodium_scene_state, legacy_scene_state_by_path.get(SODIUM_SHOALS_SCENE_PATH, {})),
		"Expected flat-save payload extraction to synthesize the active scene snapshot."
	)

	_power_switchboard.set_consumer_enabled(_power_switchboard.CONSUMER_TRAP_NETWORK, true)
	_power_switchboard.set_consumer_enabled(_power_switchboard.CONSUMER_FURNACE_BOOST, true)
	_switchboard_restore_signals = 0
	_power_switchboard.switchboard_changed.connect(_on_switchboard_changed)
	WorldSystem.clear_persistent_state()
	_world_save_data.deserialize(extracted_full)
	_power_switchboard.switchboard_changed.disconnect(_on_switchboard_changed)

	_assert(
		_scene_states_match(world_scene_state, WorldSystem.get_scene_state(WORLD_SCENE_PATH)),
		"Expected WorldSystem to restore the World snapshot from the save payload."
	)
	_assert(
		_scene_states_match(sodium_scene_state, WorldSystem.get_scene_state(SODIUM_SHOALS_SCENE_PATH)),
		"Expected WorldSystem to restore the Sodium Shoals snapshot from the save payload."
	)
	_assert(
		not _power_switchboard.is_consumer_enabled(_power_switchboard.CONSUMER_TRAP_NETWORK),
		"Expected switchboard restore to keep the trap network disabled."
	)
	_assert(
		not _power_switchboard.is_consumer_enabled(_power_switchboard.CONSUMER_FURNACE_BOOST),
		"Expected switchboard restore to keep furnace boost disabled."
	)
	_assert(_switchboard_restore_signals > 0, "Expected switchboard restore to emit switchboard_changed.")


func _run_build_restore_regression() -> void:
	var open_door := DoorScene.instantiate()
	add_child(open_door)
	await get_tree().process_frame
	open_door.restore_from_pickup({&"is_open": true})
	await get_tree().process_frame
	_assert(bool(open_door.get("is_open")), "Expected Door.restore_from_pickup() to reopen saved open doors.")
	_assert(bool(open_door.collision_shape.disabled), "Expected restored open doors to disable collision.")
	open_door.queue_free()

	var closed_door := DoorScene.instantiate()
	add_child(closed_door)
	await get_tree().process_frame
	closed_door.restore_from_pickup({&"is_open": false})
	await get_tree().process_frame
	_assert(not bool(closed_door.get("is_open")), "Expected Door.restore_from_pickup() to preserve closed doors.")
	_assert(not bool(closed_door.collision_shape.disabled), "Expected restored closed doors to keep collision enabled.")
	closed_door.queue_free()

	var extinguished_campfire := CampfireScene.instantiate()
	add_child(extinguished_campfire)
	await get_tree().process_frame
	extinguished_campfire.restore_from_pickup({
		&"burn_time_remaining": 240.0,
		&"is_lit": false,
	})
	_assert(
		not bool(extinguished_campfire.get("is_lit")),
		"Expected campfires extinguished with fuel remaining to stay extinguished after restore."
	)
	extinguished_campfire.queue_free()

	var lit_campfire := CampfireScene.instantiate()
	add_child(lit_campfire)
	await get_tree().process_frame
	lit_campfire.restore_from_pickup({
		&"burn_time_remaining": 240.0,
		&"is_lit": true,
	})
	_assert(
		bool(lit_campfire.get("is_lit")),
		"Expected lit campfires with fuel remaining to stay lit after restore."
	)
	lit_campfire.restore_from_pickup({
		&"burn_time_remaining": 0.0,
		&"is_lit": true,
	})
	_assert(
		not bool(lit_campfire.get("is_lit")),
		"Expected empty campfires to restore unlit even when older payloads say is_lit."
	)
	lit_campfire.queue_free()
	await get_tree().process_frame


func _build_scene_state(seed: String, scene_path: String, player_position: Vector2, placed_stations: Array, walls: Array) -> Dictionary:
	return {
		"world": {
			"seed": seed,
			"biomes_unlocked": ["sodium_shoals", "sulfur_flats"],
			"explored_tiles": [
				{"x": 1, "y": 2},
				{"x": 3, "y": 5},
			],
		},
		"player": {
			"position": {"x": player_position.x, "y": player_position.y},
			"health": 77.0,
			"status_effects": [&"warm"],
			"inventory": [
				{
					"id": &"sodium",
					"item_id": &"sodium",
					"quantity": 2,
				},
			],
			"active_slot_index": 0,
			"active_path": scene_path,
		},
		"base": {
			"placed_stations": placed_stations.duplicate(true),
			"walls": walls.duplicate(true),
			"storage": [],
			"chest_inventories": {},
			"defense_grid_charge": 12.5,
		},
		"resources": {
			"active_trees": [],
			"pending_tree_respawns": [],
		},
		"discoveries": [&"sulfur_flats_weather_unlocked"],
		"progression": {
			"scanner_tier": 1,
		},
	}


func _apply_scene_state_to_world_save_data(world_save_data: Node, scene_state: Dictionary) -> void:
	var world_state := scene_state.get("world", {}) as Dictionary
	world_save_data.set("world_seed", str(world_state.get("seed", "")))
	world_save_data.set("biomes_unlocked", (world_state.get("biomes_unlocked", []) as Array).duplicate(true))
	world_save_data.set("explored_tiles", (world_state.get("explored_tiles", []) as Array).duplicate(true))

	var player_state := scene_state.get("player", {}) as Dictionary
	var position := player_state.get("position", {"x": 0.0, "y": 0.0}) as Dictionary
	var player_status_effects: Array[StringName] = []
	for raw_status_effect in player_state.get("status_effects", []):
		player_status_effects.append(StringName(str(raw_status_effect)))
	var player_inventory: Array[Dictionary] = []
	for raw_item in player_state.get("inventory", []):
		if raw_item is Dictionary:
			player_inventory.append((raw_item as Dictionary).duplicate(true))
	world_save_data.set("player_position", Vector2(float(position.get("x", 0.0)), float(position.get("y", 0.0))))
	world_save_data.set("player_health", float(player_state.get("health", 100.0)))
	world_save_data.set("player_status_effects", player_status_effects)
	world_save_data.set("player_inventory", player_inventory)
	world_save_data.set("player_active_slot_index", int(player_state.get("active_slot_index", 0)))
	world_save_data.set("active_path", str(player_state.get("active_path", "")))

	var base_state := scene_state.get("base", {}) as Dictionary
	var placed_stations: Array[Dictionary] = []
	for raw_entry in base_state.get("placed_stations", []):
		if raw_entry is Dictionary:
			placed_stations.append((raw_entry as Dictionary).duplicate(true))
	var walls: Array[Dictionary] = []
	for raw_entry in base_state.get("walls", []):
		if raw_entry is Dictionary:
			walls.append((raw_entry as Dictionary).duplicate(true))
	var storage: Array[Dictionary] = []
	for raw_entry in base_state.get("storage", []):
		if raw_entry is Dictionary:
			storage.append((raw_entry as Dictionary).duplicate(true))
	world_save_data.set("placed_stations", placed_stations)
	world_save_data.set("walls", walls)
	world_save_data.set("storage", storage)
	world_save_data.set("chest_inventories", (base_state.get("chest_inventories", {}) as Dictionary).duplicate(true))
	world_save_data.set("defense_grid_charge", float(base_state.get("defense_grid_charge", 0.0)))

	var resource_state := scene_state.get("resources", {}) as Dictionary
	var active_trees: Array[Dictionary] = []
	for raw_entry in resource_state.get("active_trees", []):
		if raw_entry is Dictionary:
			active_trees.append((raw_entry as Dictionary).duplicate(true))
	var pending_tree_respawns: Array[Dictionary] = []
	for raw_entry in resource_state.get("pending_tree_respawns", []):
		if raw_entry is Dictionary:
			pending_tree_respawns.append((raw_entry as Dictionary).duplicate(true))
	world_save_data.set("active_trees", active_trees)
	world_save_data.set("pending_tree_respawns", pending_tree_respawns)

	var discoveries: Array[StringName] = []
	for raw_discovery in scene_state.get("discoveries", []):
		discoveries.append(StringName(str(raw_discovery)))
	world_save_data.set("discoveries", discoveries)
	var progression_state := scene_state.get("progression", {}) as Dictionary
	world_save_data.set("scanner_tier", int(progression_state.get("scanner_tier", 0)))


func _scene_states_match(expected: Variant, actual: Variant) -> bool:
	return expected == actual


func _on_switchboard_changed() -> void:
	_switchboard_restore_signals += 1


func _extract_scene_state_from_restore_payload(save_data: Dictionary) -> Dictionary:
	return {
		"world": (save_data.get("world", {}) as Dictionary).duplicate(true),
		"player": (save_data.get("player", {}) as Dictionary).duplicate(true),
		"base": (save_data.get("base", {}) as Dictionary).duplicate(true),
		"resources": (save_data.get("resources", {}) as Dictionary).duplicate(true),
		"discoveries": (save_data.get("discoveries", []) as Array).duplicate(true),
		"progression": (save_data.get("progression", {}) as Dictionary).duplicate(true),
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
