extends Node

const WorldSaveDataScript = preload("res://scripts/WorldSaveData.gd")

var _failures := 0


func _ready() -> void:
	_run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var source := WorldSaveDataScript.new()
	var target := WorldSaveDataScript.new()
	var backend_envelope_target := WorldSaveDataScript.new()
	var versionless_target := WorldSaveDataScript.new()
	var version_one_target := WorldSaveDataScript.new()
	var scene_state_by_path_target := WorldSaveDataScript.new()

	_seed_source_state(source)
	var serialized := source.serialize()
	var normalized_backend := source.normalize_save_envelope(serialized)
	target.deserialize(serialized)
	backend_envelope_target.deserialize(normalized_backend)

	_assert(int(serialized.get("version", 0)) == int(source.SAVE_STATE_VERSION), "Expected serialized save state version.")
	_assert(_has_backend_envelope_shape(serialized), "Expected serialized save data to use the backend-ready envelope.")
	var metadata := serialized.get("metadata", {}) as Dictionary
	var integrity := metadata.get("integrity", {}) as Dictionary
	_assert(not str(integrity.get("checksum", "")).is_empty(), "Expected serialized save data to include an integrity checksum.")
	var checksum_repair_input: Dictionary = serialized.duplicate(true)
	var checksum_repair_metadata := (checksum_repair_input.get("metadata", {}) as Dictionary).duplicate(true)
	var checksum_repair_integrity := (checksum_repair_metadata.get("integrity", {}) as Dictionary).duplicate(true)
	checksum_repair_integrity["checksum"] = "invalid"
	checksum_repair_metadata["integrity"] = checksum_repair_integrity
	checksum_repair_input["metadata"] = checksum_repair_metadata
	var repaired_backend := source.normalize_save_envelope(checksum_repair_input)
	var repaired_metadata := repaired_backend.get("metadata", {}) as Dictionary
	var repaired_integrity := repaired_metadata.get("integrity", {}) as Dictionary
	_assert(
		str(repaired_metadata.get("migration_status", "")) == "checksum_repaired",
		"Expected invalid backend checksums to be repaired during normalization."
	)
	_assert(
		str(repaired_integrity.get("checksum", "")) != "invalid",
		"Expected normalization to replace invalid backend checksums."
	)
	_assert(
		bool(source.call("_verify_integrity_checksum", repaired_backend, false)),
		"Expected repaired backend envelopes to validate cleanly."
	)
	_assert(
		_states_match(source, target),
		"Expected deserialize(serialize(state)) to preserve WorldSaveData fields. Mismatch: %s" % _describe_first_mismatch(source, target)
	)
	_assert(
		_states_match(source, backend_envelope_target),
		"Expected normalized backend envelope to preserve WorldSaveData fields. Mismatch: %s" % _describe_first_mismatch(source, backend_envelope_target)
	)

	var versionless_flat := _build_flat_payload(source, false)
	var versionless_migrated := source.normalize_save_envelope(versionless_flat)
	versionless_target.deserialize(versionless_flat)
	_assert(int(versionless_migrated.get("version", 0)) == int(source.SAVE_STATE_VERSION), "Expected versionless saves to migrate to the current save version.")
	_assert(
		str((versionless_migrated.get("metadata", {}) as Dictionary).get("migration_status", "")) == "migrated_from_flat_versionless",
		"Expected versionless saves to record migration status."
	)
	_assert(
		_states_match(source, versionless_target),
		"Expected versionless payload to migrate and preserve state. Mismatch: %s" % _describe_first_mismatch(source, versionless_target)
	)

	var version_one_flat := _build_flat_payload(source, true)
	var version_one_migrated := source.normalize_save_envelope(version_one_flat)
	version_one_target.deserialize(version_one_flat)
	_assert(int(version_one_migrated.get("version", 0)) == int(source.SAVE_STATE_VERSION), "Expected version 1 saves to migrate to the current save version.")
	_assert(
		str((version_one_migrated.get("metadata", {}) as Dictionary).get("migration_status", "")) == "migrated_from_flat_v1",
		"Expected version 1 saves to record migration status."
	)
	_assert(
		_states_match(source, version_one_target),
		"Expected version 1 payload to migrate and preserve state. Mismatch: %s" % _describe_first_mismatch(source, version_one_target)
	)

	var scene_state_by_path_save := _build_scene_state_by_path_payload(source)
	var scene_state_by_path_migrated := source.normalize_save_envelope(scene_state_by_path_save)
	scene_state_by_path_target.deserialize(scene_state_by_path_save)
	_assert(int(scene_state_by_path_migrated.get("version", 0)) == int(source.SAVE_STATE_VERSION), "Expected world_system.scene_state_by_path saves to migrate to the current save version.")
	_assert(
		str((scene_state_by_path_migrated.get("metadata", {}) as Dictionary).get("migration_status", "")) == "migrated_from_flat_v1",
		"Expected world_system.scene_state_by_path saves to record migration status."
	)
	_assert(
		_states_match(source, scene_state_by_path_target),
		"Expected world_system.scene_state_by_path payload to migrate and preserve state. Mismatch: %s" % _describe_first_mismatch(source, scene_state_by_path_target)
	)

	_assert_same_normalized_envelope_keys(normalized_backend, versionless_migrated, "backend envelope", "flat versionless")
	_assert_same_normalized_envelope_keys(normalized_backend, version_one_migrated, "backend envelope", "flat v1")
	_assert_same_normalized_envelope_keys(normalized_backend, scene_state_by_path_migrated, "backend envelope", "world_system.scene_state_by_path")

	source.free()
	target.free()
	backend_envelope_target.free()
	versionless_target.free()
	version_one_target.free()
	scene_state_by_path_target.free()

	if _failures == 0:
		print("WorldSaveDataRoundTripTest passed.")


func _seed_source_state(world_save_data: Node) -> void:
	world_save_data.set("world_seed", "123456")
	world_save_data.set("biomes_unlocked", ["sulfur_flats", "sodium_shoals"])
	world_save_data.set("explored_tiles", [
		{"x": 3, "y": 7},
		{"x": 8, "y": 11},
	])
	world_save_data.set("player_position", Vector2(144.0, 288.0))
	world_save_data.set("player_health", 63.0)
	var status_effects: Array[StringName] = [&"wet", &"burning"]
	world_save_data.set("player_status_effects", status_effects)
	world_save_data.set("player_inventory", [
		{
			"id": &"sodium",
			"item_id": &"sodium",
			"quantity": 2,
			"purity": 0.95,
		},
		{
			"id": &"mercury",
			"item_id": &"mercury",
			"quantity": 1,
			"purity": 1.0,
		},
	])
	world_save_data.set("active_path", "res://scenes/SodiumShoals.tscn")
	world_save_data.set("player_active_slot_index", 1)
	world_save_data.set("placed_stations", [
		{
			"scene_path": "res://scenes/ChemBench.tscn",
			"placed_at": Vector2i(12, 18),
			"placed_rotation_degrees": 90.0,
		},
	])
	world_save_data.set("walls", [
		{
			"scene_path": "res://scenes/Wall.tscn",
			"placed_at": Vector2i(10, 10),
		},
	])
	world_save_data.set("storage", [
		{
			"scene_path": "res://scenes/DryBox.tscn",
			"placed_at": Vector2i(14, 18),
			"container_id": "dry_box_alpha",
		},
	])
	world_save_data.set("chest_inventories", {
		"dry_box_alpha": {
			"items": {
				"sodium": {
					"id": &"sodium",
					"item_id": &"sodium",
					"quantity": 2,
				},
			},
			"slot_order": ["sodium", ""],
		},
	})
	world_save_data.set("defense_grid_charge", 42.5)
	world_save_data.set("active_trees", [
		{
			"tile_coords": Vector2i(4, 9),
			"stock": 3,
		},
	])
	world_save_data.set("pending_tree_respawns", [
		{
			"tile_coords": Vector2i(5, 9),
			"respawn_at": 120.0,
		},
	])
	var discoveries: Array[StringName] = [&"sulfur_flats_weather_unlocked", &"mercury_handling"]
	world_save_data.set("discoveries", discoveries)
	world_save_data.set("scanner_tier", 1)


func _states_match(expected: Node, actual: Node) -> bool:
	return _snapshot_state(expected) == _snapshot_state(actual)


func _snapshot_state(world_save_data: Node) -> Dictionary:
	return {
		"world_seed": world_save_data.get("world_seed"),
		"biomes_unlocked": (world_save_data.get("biomes_unlocked") as Array).duplicate(true),
		"explored_tiles": (world_save_data.get("explored_tiles") as Array).duplicate(true),
		"player_position": world_save_data.get("player_position"),
		"player_health": world_save_data.get("player_health"),
		"player_status_effects": (world_save_data.get("player_status_effects") as Array).duplicate(true),
		"player_inventory": (world_save_data.get("player_inventory") as Array).duplicate(true),
		"active_path": world_save_data.get("active_path"),
		"player_active_slot_index": world_save_data.get("player_active_slot_index"),
		"placed_stations": (world_save_data.get("placed_stations") as Array).duplicate(true),
		"walls": (world_save_data.get("walls") as Array).duplicate(true),
		"storage": (world_save_data.get("storage") as Array).duplicate(true),
		"chest_inventories": (world_save_data.get("chest_inventories") as Dictionary).duplicate(true),
		"defense_grid_charge": world_save_data.get("defense_grid_charge"),
		"active_trees": (world_save_data.get("active_trees") as Array).duplicate(true),
		"pending_tree_respawns": (world_save_data.get("pending_tree_respawns") as Array).duplicate(true),
		"discoveries": (world_save_data.get("discoveries") as Array).duplicate(true),
		"scanner_tier": world_save_data.get("scanner_tier"),
	}


func _describe_first_mismatch(expected: Node, actual: Node) -> String:
	var expected_snapshot := _snapshot_state(expected)
	var actual_snapshot := _snapshot_state(actual)
	for key in expected_snapshot.keys():
		if expected_snapshot[key] == actual_snapshot.get(key):
			continue
		return "%s expected=%s actual=%s" % [str(key), var_to_str(expected_snapshot[key]), var_to_str(actual_snapshot.get(key))]
	return "unknown"


func _build_flat_payload(world_save_data: Node, include_version: bool) -> Dictionary:
	var flat_payload := {
		"metadata": {
			"slot_id": 1,
			"saved_at_unix": 123456789,
			"current_day": 2,
			"current_scene_path": str(world_save_data.get("active_path")),
		},
		"game_manager": {
			"current_day": 2,
			"current_scene_path": str(world_save_data.get("active_path")),
		},
		"world": {
			"seed": world_save_data.get("world_seed"),
			"biomes_unlocked": (world_save_data.get("biomes_unlocked") as Array).duplicate(true),
			"explored_tiles": (world_save_data.get("explored_tiles") as Array).duplicate(true),
		},
		"player": {
			"position": {
				"x": (world_save_data.get("player_position") as Vector2).x,
				"y": (world_save_data.get("player_position") as Vector2).y,
			},
			"health": world_save_data.get("player_health"),
			"status_effects": (world_save_data.get("player_status_effects") as Array).duplicate(true),
			"inventory": (world_save_data.get("player_inventory") as Array).duplicate(true),
			"active_path": world_save_data.get("active_path"),
			"active_slot_index": world_save_data.get("player_active_slot_index"),
		},
		"base": {
			"placed_stations": (world_save_data.get("placed_stations") as Array).duplicate(true),
			"walls": (world_save_data.get("walls") as Array).duplicate(true),
			"storage": (world_save_data.get("storage") as Array).duplicate(true),
			"chest_inventories": (world_save_data.get("chest_inventories") as Dictionary).duplicate(true),
			"defense_grid_charge": world_save_data.get("defense_grid_charge"),
		},
		"resources": {
			"active_trees": (world_save_data.get("active_trees") as Array).duplicate(true),
			"pending_tree_respawns": (world_save_data.get("pending_tree_respawns") as Array).duplicate(true),
		},
		"discoveries": (world_save_data.get("discoveries") as Array).duplicate(true),
		"progression": {
			"scanner_tier": world_save_data.get("scanner_tier"),
		},
	}
	if include_version:
		flat_payload["version"] = 1
	return flat_payload


func _build_scene_state_by_path_payload(world_save_data: Node) -> Dictionary:
	var current_scene_state := _build_flat_payload(world_save_data, true)
	var current_scene_path := str(world_save_data.get("active_path"))
	var root_scene_path := "res://scenes/World.tscn"
	return {
		"version": 1,
		"metadata": {
			"slot_id": 1,
			"saved_at_unix": 123456789,
			"current_day": 2,
			"current_scene_path": current_scene_path,
		},
		"game_manager": {
			"current_day": 2,
			"current_scene_path": current_scene_path,
		},
		"world_system": {
			"current_seed": int(str(world_save_data.get("world_seed"))),
			"scene_seeds": {
				root_scene_path: 777,
				current_scene_path: int(str(world_save_data.get("world_seed"))),
			},
			"scene_state_by_path": {
				root_scene_path: {
					"world": {
						"seed": "777",
						"biomes_unlocked": ["world"],
						"explored_tiles": [],
					},
					"player": {
						"position": {"x": 32.0, "y": 32.0},
						"health": 100.0,
						"status_effects": [],
						"inventory": [],
						"active_path": root_scene_path,
						"active_slot_index": 0,
					},
					"base": {
						"placed_stations": [],
						"walls": [],
						"storage": [],
						"chest_inventories": {},
						"defense_grid_charge": 0.0,
					},
					"resources": {
						"active_trees": [],
						"pending_tree_respawns": [],
					},
					"discoveries": [],
					"progression": {
						"scanner_tier": 0,
					},
				},
				current_scene_path: {
					"world": (current_scene_state.get("world", {}) as Dictionary).duplicate(true),
					"player": (current_scene_state.get("player", {}) as Dictionary).duplicate(true),
					"base": (current_scene_state.get("base", {}) as Dictionary).duplicate(true),
					"resources": (current_scene_state.get("resources", {}) as Dictionary).duplicate(true),
					"discoveries": (current_scene_state.get("discoveries", []) as Array).duplicate(true),
					"progression": (current_scene_state.get("progression", {}) as Dictionary).duplicate(true),
				},
			},
		},
		"element_database": {},
		"discovery_log": {},
		"research_objectives": {},
		"power_switchboard": {},
		"weather_system": {},
		"cold_system": {},
	}


func _has_backend_envelope_shape(save_data: Dictionary) -> bool:
	for key in ["version", "metadata", "game_manager", "world_system", "current_scene_state", "global_systems"]:
		if not save_data.has(key):
			return false
	return true


func _assert_same_normalized_envelope_keys(expected: Dictionary, actual: Dictionary, expected_label: String, actual_label: String) -> void:
	_assert(
		_dictionary_key_set(expected) == _dictionary_key_set(actual),
		"Expected normalized top-level keys to match for %s and %s." % [expected_label, actual_label]
	)
	_assert(
		_dictionary_key_set(expected.get("global_systems", {}) as Dictionary)
			== _dictionary_key_set(actual.get("global_systems", {}) as Dictionary),
		"Expected normalized global_systems keys to match for %s and %s." % [expected_label, actual_label]
	)
	_assert(
		_dictionary_key_set(expected.get("current_scene_state", {}) as Dictionary)
			== _dictionary_key_set(actual.get("current_scene_state", {}) as Dictionary),
		"Expected normalized current_scene_state keys to match for %s and %s." % [expected_label, actual_label]
	)


func _dictionary_key_set(dictionary: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in dictionary.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
