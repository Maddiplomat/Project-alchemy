extends Node

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"

const WALL_SCENE := preload("res://scenes/Wall.tscn")
const DOOR_SCENE := preload("res://scenes/Door.tscn")
const CAMPFIRE_SCENE := preload("res://scenes/Campfire.tscn")
const STORAGE_CHEST_SCENE := preload("res://scenes/StorageChest.tscn")
const POWERED_LIGHT_POST_SCENE := preload("res://scenes/PoweredLightPost.tscn")
const ELECTRIC_TRAP_SCENE := preload("res://scenes/ElectricTrap.tscn")

const SLOT_PATHS := [
	"user://saves/slot_1.json",
	"user://saves/slot_1.bak.json",
	"user://saves/slot_1.save",
]

var _failures := 0
var _slot_backups: Dictionary = {}
var _placed_tile_by_label: Dictionary[StringName, Vector2i] = {}
var _harvested_tree_tile := Vector2i(-1, -1)
var _harvested_tree_remaining := -1
var _expected_inventory_snapshot: Dictionary = {}
var _expected_chest_id: StringName = &""
var _expected_chest_slot_item: Dictionary = {}
var _scene_tree: SceneTree = null


func _ready() -> void:
	_scene_tree = get_tree()
	call_deferred("_start")


func _start() -> void:
	var root := _scene_tree.root
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	root.add_child(self)
	owner = null
	await _run_test()
	_restore_save_slot_backups()
	_scene_tree.quit(1 if _failures > 0 else 0)


func _run_test() -> void:
	_backup_save_slot()
	_clear_test_save_slot()

	GameManager.start_new_game(GameManager.SessionMode.OFFLINE, 1)
	await _change_scene_and_wait(WORLD_SCENE_PATH)

	await _seed_world_runtime_state()
	var save_result := GameManager.request_save(GameManager.SaveTrigger.MANUAL)
	_assert(bool(save_result.get(&"success", false)), "Expected the integration test save to succeed.")

	await _change_scene_and_wait(MAIN_MENU_SCENE_PATH)
	GameManager.request_load_game(1)
	await _wait_for_scene_reload(WORLD_SCENE_PATH)
	await _assert_loaded_runtime_state()

	WeatherSystem.restore_persistent_state({
		"current_state": WeatherSystem.WeatherState.CLEAR,
		"state_time_remaining": 12.0,
		"next_state": WeatherSystem.WeatherState.ACID_MIST,
		"warning_lead_time": 15.0,
		"warning_active": true,
		"rare_weather_unlocked": true,
	})
	var warning_save_result := GameManager.request_save(GameManager.SaveTrigger.MANUAL)
	_assert(bool(warning_save_result.get(&"success", false)), "Expected the warning-state save to succeed.")

	await _change_scene_and_wait(MAIN_MENU_SCENE_PATH)
	GameManager.request_load_game(1)
	await _wait_for_scene_reload(WORLD_SCENE_PATH)
	_assert_loaded_warning_state()

	if _failures == 0:
		print("SaveLoadIntegrationTest passed.")


func _seed_world_runtime_state() -> void:
	var world := _scene_tree.current_scene
	_assert(world != null, "Expected World scene to be active before seeding state.")
	if world == null:
		return
	_assert(world.get_node_or_null("Furnace") == null, "Expected a new game world to start without an authored Furnace node.")
	_assert(world.get_node_or_null("ChemBench") == null, "Expected a new game world to start without an authored ChemBench node.")
	var player := GameManager.get_player()
	_assert(player != null, "Expected the player to be registered in World.")
	if player == null:
		return
	var ground := world.get_node_or_null("Ground") as TileMapLayer
	_assert(ground != null, "Expected World to expose a Ground TileMapLayer.")
	if ground == null:
		return

	var placement_tiles := _find_free_tiles(world, ground, 6)
	_assert(placement_tiles.size() == 6, "Expected to find six free build tiles in World.")
	if placement_tiles.size() != 6:
		return

	_spawn_placed_object(world, ground, WALL_SCENE, placement_tiles[0], &"wall")
	var door := _spawn_placed_object(world, ground, DOOR_SCENE, placement_tiles[1], &"door")
	var campfire := _spawn_placed_object(world, ground, CAMPFIRE_SCENE, placement_tiles[2], &"campfire")
	var chest := _spawn_placed_object(world, ground, STORAGE_CHEST_SCENE, placement_tiles[3], &"storage")
	var light_post := _spawn_placed_object(world, ground, POWERED_LIGHT_POST_SCENE, placement_tiles[4], &"light_post")
	var trap := _spawn_placed_object(world, ground, ELECTRIC_TRAP_SCENE, placement_tiles[5], &"trap")
	await _scene_tree.process_frame

	_assert(door != null and campfire != null and chest != null and light_post != null and trap != null, "Expected all representative objects to spawn.")
	if door == null or campfire == null or chest == null or light_post == null or trap == null:
		return

	door.restore_from_pickup({&"is_open": true})
	campfire.restore_from_pickup({
		&"burn_time_remaining": 240.0,
		&"is_lit": false,
		&"refuel_wood_units_loaded": 2,
	})
	await _scene_tree.process_frame

	var tree := _find_harvestable_tree()
	_assert(tree != null, "Expected World to contain a harvestable tree for the integration test.")
	if tree != null:
		InventoryManager.active_slot_index = 1
		InventoryManager.restore_slots([
			{},
			{
				"id": &"iron_axe",
				"item_id": &"iron_axe",
				"display_name": "Iron Axe",
				"category": InventoryManager.InventoryItemCategory.TOOL,
				"risk_level": InventoryManager.InventoryRiskLevel.NONE,
				"quantity": 1,
				"purity": 1.0,
				"unit_weight": 2.0,
				"weight": 2.0,
				"durability": 0.75,
				"max_durability": 1.0,
			},
			{},
			{},
			{},
		], false)
		player.global_position = tree.global_position
		await _scene_tree.process_frame
		var harvest_succeeded := false
		for _attempt in range(3):
			if bool(tree.call("_harvest")):
				harvest_succeeded = true
				break
			await _scene_tree.process_frame
		_assert(harvest_succeeded, "Expected the test tree harvest to succeed.")
		if harvest_succeeded:
			_harvested_tree_tile = tree.tile_coords
			_harvested_tree_remaining = tree.remaining_wood

	ElementDatabase.mark_element_scanned(&"wood")
	ElementDatabase.mark_element_scanned(&"stone")
	ElementDatabase.mark_element_scanned(&"iron")
	if DiscoveryLog != null and DiscoveryLog.has_method("log_progression_discovery"):
		DiscoveryLog.log_progression_discovery(
			ResearchObjectives.SULFUR_FLATS_WEATHER_ENTRY_ID,
			"Weather Shift Logged",
			"Rare weather tracked for integration coverage."
		)
	ResearchObjectives.sync_with_runtime_state()

	var chest_item := {
		"id": &"energy_cell",
		"item_id": &"energy_cell",
		"display_name": "Energy Cell",
		"category": InventoryManager.InventoryItemCategory.ELEMENT,
		"risk_level": InventoryManager.InventoryRiskLevel.NONE,
		"quantity": 1,
		"purity": 0.88,
		"unit_weight": 1.0,
		"weight": 1.0,
		"charge": 0.55,
		"max_charge": 1.0,
	}
	StorageManager.call("_store_item_into_slot", chest.chest_id, chest_item, 1, 0)
	GameManager.mark_dirty()
	_expected_chest_id = chest.chest_id
	_expected_chest_slot_item = _normalize_storage_item(StorageManager.get_slot_item(chest.chest_id, 0))

	var inventory_payload: Array = [
		{
			"id": &"wood",
			"item_id": &"wood",
			"display_name": "Wood",
			"category": InventoryManager.InventoryItemCategory.ELEMENT,
			"risk_level": InventoryManager.InventoryRiskLevel.NONE,
			"quantity": 3,
			"purity": 1.0,
			"unit_weight": 1.0,
			"weight": 1.0,
		},
		{
			"id": &"iron_axe",
			"item_id": &"iron_axe",
			"display_name": "Iron Axe",
			"category": InventoryManager.InventoryItemCategory.TOOL,
			"risk_level": InventoryManager.InventoryRiskLevel.NONE,
			"quantity": 1,
			"purity": 1.0,
			"unit_weight": 2.0,
			"weight": 2.0,
			"durability": 0.65,
			"max_durability": 1.0,
		},
		{
			"id": &"energy_cell",
			"item_id": &"energy_cell",
			"display_name": "Energy Cell",
			"category": InventoryManager.InventoryItemCategory.ELEMENT,
			"risk_level": InventoryManager.InventoryRiskLevel.NONE,
			"quantity": 1,
			"purity": 0.91,
			"unit_weight": 1.0,
			"weight": 1.0,
			"charge": 0.42,
			"max_charge": 1.0,
		},
		{
			"id": &"sodium",
			"item_id": &"sodium",
			"display_name": "Sodium",
			"category": InventoryManager.InventoryItemCategory.ELEMENT,
			"risk_level": InventoryManager.InventoryRiskLevel.HIGH,
			"quantity": 2,
			"purity": 0.76,
			"unit_weight": 1.0,
			"weight": 1.0,
		},
		{},
	]
	InventoryManager.active_slot_index = 2
	InventoryManager.restore_slots(inventory_payload, false)
	_expected_inventory_snapshot = _snapshot_inventory_state()

	var power_switchboard := EventBus.get_power_switchboard()
	if power_switchboard != null:
		power_switchboard.set_consumer_enabled(power_switchboard.CONSUMER_PERIMETER_LIGHTS, false)
		power_switchboard.set_consumer_enabled(power_switchboard.CONSUMER_TRAP_NETWORK, false)
		power_switchboard.set_consumer_enabled(power_switchboard.CONSUMER_FURNACE_BOOST, false)

	var base_grid := EventBus.get_base_grid()
	if base_grid != null and base_grid.has_method("restore_charge_level"):
		base_grid.restore_charge_level(18.0)

	WeatherSystem.restore_persistent_state({
		"current_state": WeatherSystem.WeatherState.RAIN,
		"state_time_remaining": 30.0,
		"next_state": WeatherSystem.WeatherState.CLEAR,
		"warning_lead_time": -1.0,
		"warning_active": false,
		"rare_weather_unlocked": true,
	})
	var cold_system := EventBus.get_cold_system()
	if cold_system != null and cold_system.has_method("restore_persistent_state"):
		cold_system.restore_persistent_state({
			"cold_level": 99.0,
			"is_player_warmed": false,
			"cold_damage_timer": 1.5,
		})

	GameManager.mark_dirty()


func _assert_loaded_runtime_state() -> void:
	var world := _scene_tree.current_scene
	_assert(world != null and str(world.scene_file_path) == WORLD_SCENE_PATH, "Expected World to be active after load.")
	if world == null:
		return

	_assert(int(WeatherSystem.get_current_state()) == WeatherSystem.WeatherState.RAIN, "Expected rain to remain active after load.")
	_assert(_is_approx_equal(float(WeatherSystem.get_state_time_remaining()), 30.0, 2.5), "Expected rain remaining time to survive load.")
	_assert(not bool(WeatherSystem.is_transition_warning_active()), "Expected the rain save to reload without a warning state.")

	var cold_state: Dictionary = EventBus.get_cold_system().capture_persistent_state() if EventBus.get_cold_system() != null else {}
	_assert(_is_approx_equal(float(cold_state.get("cold_level", 0.0)), 99.0, 0.1), "Expected cold level to survive load.")
	_assert(_is_approx_equal(float(cold_state.get("cold_damage_timer", 0.0)), 1.5, 0.2), "Expected cold damage timer to survive load.")

	_assert(_snapshot_inventory_state() == _expected_inventory_snapshot, "Expected inventory slots, held item, weight, and volatile risk to restore exactly.")
	_assert(not _expected_chest_id.is_empty(), "Expected the integration test chest id to be captured.")
	if not _expected_chest_id.is_empty():
		var actual_chest_slot_item := _normalize_storage_item(StorageManager.get_slot_item(_expected_chest_id, 0))
		_assert(actual_chest_slot_item == _expected_chest_slot_item, "Expected chest inventory contents to survive save/load.")

	var power_switchboard := EventBus.get_power_switchboard()
	_assert(power_switchboard != null, "Expected power switchboard service after load.")
	if power_switchboard != null:
		_assert(not power_switchboard.is_consumer_enabled(power_switchboard.CONSUMER_PERIMETER_LIGHTS), "Expected perimeter lights to stay disabled after load.")
		_assert(not power_switchboard.is_consumer_enabled(power_switchboard.CONSUMER_TRAP_NETWORK), "Expected trap network to stay disabled after load.")
		_assert(not power_switchboard.is_consumer_enabled(power_switchboard.CONSUMER_FURNACE_BOOST), "Expected furnace boost to stay disabled after load.")

	var base_grid := EventBus.get_base_grid()
	_assert(base_grid != null and _is_approx_equal(float(base_grid.get_charge_state()), 18.0, 0.1), "Expected base charge to survive load.")

	_assert(ElementDatabase.is_element_scanned(&"wood"), "Expected scanned wood to survive load.")
	_assert(ElementDatabase.is_element_scanned(&"stone"), "Expected scanned stone to survive load.")
	_assert(ElementDatabase.is_element_scanned(&"iron"), "Expected scanned iron to survive load.")
	_assert(bool(ResearchObjectives.get_objective(&"scan_starters").get("completed", false)), "Expected the first objective to remain completed after load.")

	if _harvested_tree_tile != Vector2i(-1, -1):
		var restored_tree := _find_tree_at_tile(_harvested_tree_tile)
		_assert(restored_tree != null, "Expected the harvested tree to reload.")
		if restored_tree != null:
			_assert(int(restored_tree.remaining_wood) == _harvested_tree_remaining, "Expected harvested tree state to survive load.")

	var door := _find_placed_node_at_tile(&"placed_doors", _placed_tile_by_label.get(&"door", Vector2i(-1, -1)))
	_assert(door != null and bool(door.is_open), "Expected the placed door to restore open.")
	var campfire := _find_placed_node_at_tile(&"placed_stations", _placed_tile_by_label.get(&"campfire", Vector2i(-1, -1)), &"campfire")
	_assert(campfire != null and not bool(campfire.is_lit), "Expected the placed campfire to restore extinguished.")
	var chest := _find_placed_node_at_tile(&"placed_storage", _placed_tile_by_label.get(&"storage", Vector2i(-1, -1)))
	_assert(chest != null, "Expected the placed storage chest to reload.")
	var light_post := _find_placed_node_at_tile(&"placed_stations", _placed_tile_by_label.get(&"light_post", Vector2i(-1, -1)), &"powered_light_post")
	_assert(light_post != null, "Expected the placed powered light to reload.")
	var trap := _find_placed_node_at_tile(&"placed_stations", _placed_tile_by_label.get(&"trap", Vector2i(-1, -1)), &"electric_trap")
	_assert(trap != null, "Expected the placed electric trap to reload.")


func _assert_loaded_warning_state() -> void:
	_assert(int(WeatherSystem.get_current_state()) == WeatherSystem.WeatherState.CLEAR, "Expected clear weather to restore for the warning-state save.")
	_assert(bool(WeatherSystem.is_transition_warning_active()), "Expected warning state to remain active after load.")
	_assert(int(WeatherSystem.get_transition_warning_state()) == WeatherSystem.WeatherState.ACID_MIST, "Expected warning target state to survive load.")
	_assert(_is_approx_equal(float(WeatherSystem.get_transition_warning_seconds_remaining()), 12.0, 2.0), "Expected warning remaining time to survive load.")
	_assert(_snapshot_inventory_state() == _expected_inventory_snapshot, "Expected inventory restore to remain stable across repeated loads.")


func _spawn_placed_object(world: Node, ground: TileMapLayer, scene: PackedScene, tile_coords: Vector2i, label: StringName) -> Node2D:
	var instance := scene.instantiate()
	if not (instance is Node2D):
		if instance != null:
			instance.free()
		return null
	var node := instance as Node2D
	world.add_child(node)
	node.global_position = ground.to_global(ground.map_to_local(tile_coords))
	if node.has_method("configure_placed_object"):
		node.call("configure_placed_object", tile_coords)
	_placed_tile_by_label[label] = tile_coords
	return node


func _find_free_tiles(world: Node, ground: TileMapLayer, count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var player := GameManager.get_player()
	var origin_tile := Vector2i(32, 32)
	if player != null:
		origin_tile = ground.local_to_map(ground.to_local(player.global_position))
	for radius in range(2, 18):
		for y in range(origin_tile.y - radius, origin_tile.y + radius + 1):
			for x in range(origin_tile.x - radius, origin_tile.x + radius + 1):
				var tile_coords := Vector2i(x, y)
				if found.has(tile_coords):
					continue
				if not _is_tile_placeable(world, ground, tile_coords):
					continue
				found.append(tile_coords)
				if found.size() >= count:
					return found
	return found


func _is_tile_placeable(world: Node, ground: TileMapLayer, tile_coords: Vector2i) -> bool:
	if ground.get_cell_source_id(tile_coords) == -1:
		return false
	var current_scene := _scene_tree.current_scene
	if current_scene == null or current_scene != world:
		return false
	var objects_layer := world.get_node_or_null("Objects") as TileMapLayer
	if objects_layer != null and objects_layer.get_cell_source_id(tile_coords) != -1:
		return false
	for node in _scene_tree.get_nodes_in_group(&"placed_objects"):
		if not is_instance_valid(node):
			continue
		if node.has_method("get_occupied_tile_coords"):
			var occupied_tiles: Array = node.call("get_occupied_tile_coords")
			if occupied_tiles.has(tile_coords):
				return false
		elif node.has_meta(&"build_tile_coords") and node.get_meta(&"build_tile_coords") == tile_coords:
			return false
	return true


func _find_harvestable_tree() -> TreeResource:
	for node in _scene_tree.get_nodes_in_group(&"harvestable_trees"):
		var tree := node as TreeResource
		if tree == null or not is_instance_valid(tree):
			continue
		return tree
	return null


func _find_tree_at_tile(tile_coords: Vector2i) -> TreeResource:
	for node in _scene_tree.get_nodes_in_group(&"harvestable_trees"):
		var tree := node as TreeResource
		if tree == null or not is_instance_valid(tree):
			continue
		if tree.tile_coords == tile_coords:
			return tree
	return null


func _find_placed_node_at_tile(group_name: StringName, tile_coords: Vector2i, object_type: StringName = &"") -> Node:
	for node in _scene_tree.get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		if object_type != &"" and StringName(str(node.get("object_type"))) != object_type:
			continue
		if node.has_method("get_placed_tile_coords") and node.call("get_placed_tile_coords") == tile_coords:
			return node
		if node.has_meta(&"build_tile_coords") and node.get_meta(&"build_tile_coords") == tile_coords:
			return node
	return null


func _snapshot_inventory_state() -> Dictionary:
	var slot_payload: Array[Dictionary] = []
	for slot_index in range(InventoryManager.DEFAULT_SLOT_COUNT):
		slot_payload.append(InventoryManager.get_slot_data(slot_index).duplicate(true))
	return {
		"slots": slot_payload,
		"active_slot_index": int(InventoryManager.active_slot_index),
		"held_item_id": InventoryManager.get_held_item_id(),
		"total_weight": InventoryManager.total_weight,
		"carry_capacity": InventoryManager.carry_capacity,
		"volatile_risk_item_ids": InventoryManager.volatile_risk_item_ids.duplicate(true),
	}


func _normalize_storage_item(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	return {
		"id": StringName(str(item.get("id", ""))),
		"item_id": StringName(str(item.get("item_id", ""))),
		"display_name": str(item.get("display_name", "")),
		"category": int(item.get("category", 0)),
		"risk_level": int(item.get("risk_level", 0)),
		"quantity": int(item.get("quantity", 0)),
		"purity": float(item.get("purity", 0.0)),
		"unit_weight": float(item.get("unit_weight", 0.0)),
		"weight": float(item.get("weight", 0.0)),
		"charge": float(item.get("charge", 0.0)),
		"max_charge": float(item.get("max_charge", 0.0)),
	}


func _change_scene_and_wait(scene_path: String) -> void:
	var previous_scene := _scene_tree.current_scene
	var previous_scene_id := previous_scene.get_instance_id() if previous_scene != null else -1
	var scene_error := _scene_tree.change_scene_to_file(scene_path)
	_assert(scene_error == OK, "Expected scene change to %s to succeed." % scene_path)
	await _wait_for_scene_reload(scene_path, previous_scene_id)


func _wait_for_scene_reload(scene_path: String, previous_scene_id: int = -1) -> void:
	var attempts := 0
	while attempts < 300:
		await _scene_tree.process_frame
		var current_scene := _scene_tree.current_scene
		if current_scene == null:
			attempts += 1
			continue
		if str(current_scene.scene_file_path) != scene_path:
			attempts += 1
			continue
		if previous_scene_id != -1 and current_scene.get_instance_id() == previous_scene_id:
			attempts += 1
			continue
		return
	_assert(false, "Timed out waiting for scene reload: %s" % scene_path)


func _backup_save_slot() -> void:
	_slot_backups.clear()
	for save_path in SLOT_PATHS:
		var absolute_path := ProjectSettings.globalize_path(save_path)
		var backup_state := {
			"existed": FileAccess.file_exists(save_path),
			"bytes": PackedByteArray(),
			"absolute_path": absolute_path,
		}
		if bool(backup_state["existed"]):
			var file := FileAccess.open(save_path, FileAccess.READ)
			if file != null:
				backup_state["bytes"] = file.get_buffer(file.get_length())
				file.close()
		_slot_backups[save_path] = backup_state


func _clear_test_save_slot() -> void:
	for save_path in SLOT_PATHS:
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _restore_save_slot_backups() -> void:
	for save_path in SLOT_PATHS:
		var backup_state: Dictionary = _slot_backups.get(save_path, {})
		var absolute_path := ProjectSettings.globalize_path(save_path)
		if bool(backup_state.get("existed", false)):
			var file := FileAccess.open(save_path, FileAccess.WRITE)
			if file == null:
				continue
			file.store_buffer(backup_state.get("bytes", PackedByteArray()))
			file.close()
		elif FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(absolute_path)


func _is_approx_equal(actual: float, expected: float, tolerance: float) -> bool:
	return absf(actual - expected) <= tolerance


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
