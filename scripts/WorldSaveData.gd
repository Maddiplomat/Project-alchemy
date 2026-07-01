extends Node

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


func serialize() -> Dictionary:
	var data := {}

	data["world"] = {
		"seed": world_seed,
		"biomes_unlocked": biomes_unlocked.duplicate(true),
		"explored_tiles": explored_tiles.duplicate(true)
	}

	data["player"] = {
		"position": {"x": player_position.x, "y": player_position.y},
		"health": player_health,
		"status_effects": player_status_effects.duplicate(true),
		"inventory": player_inventory.duplicate(true),
		"active_path": active_path,
	}

	data["base"] = {
		"placed_stations": placed_stations.duplicate(true),
		"walls": walls.duplicate(true),
		"storage": storage.duplicate(true),
		"chest_inventories": chest_inventories.duplicate(true),
		"defense_grid_charge": defense_grid_charge,
	}

	data["resources"] = {
		"active_trees": active_trees.duplicate(true),
		"pending_tree_respawns": pending_tree_respawns.duplicate(true),
	}

	data["discoveries"] = discoveries.duplicate(true)
	data["progression"] = {
		"scanner_tier": scanner_tier,
	}

	return data

func deserialize(data: Dictionary) -> void:
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
		player_status_effects = (player_data.get("status_effects", []) as Array).duplicate(true)
		player_inventory = []
		for raw_item in player_data.get("inventory", []):
			if raw_item is Dictionary:
				player_inventory.append((raw_item as Dictionary).duplicate(true))
			else:
				player_inventory.append({})
		active_path = str(player_data.get("active_path", ""))
		if has_node("/root/GameManager"):
			var gm = get_node("/root/GameManager")
			if is_instance_valid(gm) and gm.get("player") != null:
				var player = gm.player
				player.global_position = player_position
				
				if player.has_node("HealthSystem"):
					player.get_node("HealthSystem").current_health = player_health
					
		if has_node("/root/InventoryManager"):
			var inv = get_node("/root/InventoryManager")
			inv.clear_inventory()
			for i in range(mini(player_inventory.size(), inv.DEFAULT_SLOT_COUNT)):
				var item_data = player_inventory[i]
				if not item_data.is_empty():
					var qty = item_data.get("quantity", 1)
					inv.add_item(item_data, qty)
					inv.move_item_to_slot(item_data.get("id", ""), i)
					
	if data.has("base"):
		var base_data: Dictionary = data["base"]
		placed_stations = base_data.get("placed_stations", [])
		walls = base_data.get("walls", [])
		storage = base_data.get("storage", [])
		chest_inventories = base_data.get("chest_inventories", {})
		defense_grid_charge = float(base_data.get("defense_grid_charge", 0.0))
		var base_grid := EventBus.get_base_grid()
		if base_grid != null and base_grid.has_method("restore_charge_level"):
			base_grid.restore_charge_level(defense_grid_charge)
		
		if has_node("/root/BuildSystem"):
			var build_sys = get_node("/root/BuildSystem")
			if build_sys.has_method("import_from_world_save_data"):
				build_sys.import_from_world_save_data(self)
		if has_node("/root/StorageManager"):
			var storage_manager = get_node("/root/StorageManager")
			if storage_manager.has_method("import_from_world_save_data"):
				storage_manager.import_from_world_save_data(self)

	if data.has("resources"):
		var resource_data: Dictionary = data["resources"]
		active_trees = resource_data.get("active_trees", [])
		pending_tree_respawns = resource_data.get("pending_tree_respawns", [])
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.has_method("import_tree_state"):
			current_scene.call("import_tree_state", active_trees, pending_tree_respawns)
	else:
		clear_tree_state()
				
	if data.has("discoveries"):
		discoveries = []
		for raw_discovery in data["discoveries"]:
			discoveries.append(StringName(str(raw_discovery)))
		if has_node("/root/DiscoveryLog"):
			var dlog = get_node("/root/DiscoveryLog")
			if dlog.has_method("restore_discoveries"):
				dlog.restore_discoveries(discoveries)
			elif "unlocked_elements" in dlog:
				dlog.unlocked_elements = discoveries.duplicate(true)

	if data.has("progression") and has_node("/root/GameManager"):
		var progression_data: Dictionary = data["progression"]
		scanner_tier = int(progression_data.get("scanner_tier", 0))
		var gm = get_node("/root/GameManager")
		if gm != null and gm.has_method("restore_scanner_tier"):
			gm.restore_scanner_tier(scanner_tier)


func _sync_world_state() -> void:
	var world_system := get_node_or_null("/root/WorldSystem")
	if world_system != null and world_system.has_method("get_seed"):
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

	var inv := get_node_or_null("/root/InventoryManager")
	if inv != null:
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
