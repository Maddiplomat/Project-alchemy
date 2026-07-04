extends Node

const WorldSaveDataScript = preload("res://scripts/WorldSaveData.gd")

var _failures := 0


func _ready() -> void:
	_run_test()
	get_tree().quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	var source := WorldSaveDataScript.new()
	var target := WorldSaveDataScript.new()
	var versionless_target := WorldSaveDataScript.new()
	var version_one_target := WorldSaveDataScript.new()

	_seed_source_state(source)
	var serialized := source.serialize()
	target.deserialize(serialized)

	_assert(int(serialized.get("version", 0)) == int(source.SAVE_STATE_VERSION), "Expected serialized save state version.")
	_assert(_has_backend_envelope_shape(serialized), "Expected serialized save data to use the backend-ready envelope.")
	var metadata := serialized.get("metadata", {}) as Dictionary
	var integrity := metadata.get("integrity", {}) as Dictionary
	_assert(not str(integrity.get("checksum", "")).is_empty(), "Expected serialized save data to include an integrity checksum.")
	_assert(
		_states_match(source, target),
		"Expected deserialize(serialize(state)) to preserve WorldSaveData fields. Mismatch: %s" % _describe_first_mismatch(source, target)
	)

	var versionless_flat := _build_flat_payload(source, false)
	var versionless_migrated := source._migrate_save_data(versionless_flat)
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
	var version_one_migrated := source._migrate_save_data(version_one_flat)
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

	source.free()
	target.free()
	versionless_target.free()
	version_one_target.free()

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


func _has_backend_envelope_shape(save_data: Dictionary) -> bool:
	for key in ["version", "metadata", "game_manager", "world_system", "current_scene_state", "global_systems"]:
		if not save_data.has(key):
			return false
	return true


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
