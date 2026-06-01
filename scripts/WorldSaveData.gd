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

func serialize() -> Dictionary:
	var data := {}
	
	# World
	data["world"] = {
		"seed": world_seed,
		"biomes_unlocked": biomes_unlocked.duplicate(true),
		"explored_tiles": explored_tiles.duplicate(true)
	}
	
	# Player
	var player_data := {
		"position": {"x": 0.0, "y": 0.0},
		"health": 100.0,
		"status_effects": [],
		"inventory": [],
		"active_path": ""
	}
	
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		if is_instance_valid(gm) and gm.get("player") != null:
			var player = gm.player
			player_data["position"] = {"x": player.global_position.x, "y": player.global_position.y}
			if player.has_node("HealthSystem"):
				player_data["health"] = player.get_node("HealthSystem").current_health
	
	if has_node("/root/InventoryManager"):
		var inv = get_node("/root/InventoryManager")
		var inv_items = []
		for i in range(inv.DEFAULT_SLOT_COUNT):
			var item = inv.get_slot_item(i)
			inv_items.append(item.duplicate(true) if not item.is_empty() else {})
		player_data["inventory"] = inv_items
	
	data["player"] = player_data
	
	# Base
	if has_node("/root/BuildSystem"):
		get_node("/root/BuildSystem").export_to_world_save_data(self)
	
	var base_data := {
		"placed_stations": placed_stations.duplicate(true),
		"walls": walls.duplicate(true),
		"storage": storage.duplicate(true)
	}
	data["base"] = base_data

	clear_tree_state()
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("export_tree_state"):
		var tree_state: Dictionary = current_scene.call("export_tree_state")
		active_trees = (tree_state.get("active_trees", []) as Array).duplicate(true)
		pending_tree_respawns = (tree_state.get("pending_tree_respawns", []) as Array).duplicate(true)
	data["resources"] = {
		"active_trees": active_trees.duplicate(true),
		"pending_tree_respawns": pending_tree_respawns.duplicate(true),
	}
	
	# Discoveries
	var discoveries := []
	if has_node("/root/DiscoveryLog"):
		var dlog = get_node("/root/DiscoveryLog")
		if dlog.has_method("get_all_discoveries"):
			discoveries = dlog.get_all_discoveries().duplicate(true)
		elif "unlocked_elements" in dlog:
			discoveries = dlog.unlocked_elements.duplicate(true)
	data["discoveries"] = discoveries
	
	return data

func deserialize(data: Dictionary) -> void:
	if data.has("world"):
		var world_data: Dictionary = data["world"]
		world_seed = world_data.get("seed", "")
		biomes_unlocked = world_data.get("biomes_unlocked", [])
		explored_tiles = world_data.get("explored_tiles", [])
		
	if data.has("player"):
		var player_data: Dictionary = data["player"]
		if has_node("/root/GameManager"):
			var gm = get_node("/root/GameManager")
			if is_instance_valid(gm) and gm.get("player") != null:
				var player = gm.player
				var pos = player_data.get("position", {"x": 0.0, "y": 0.0})
				player.global_position = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
				
				if player.has_node("HealthSystem"):
					player.get_node("HealthSystem").current_health = player_data.get("health", 100.0)
					
		if has_node("/root/InventoryManager"):
			var inv = get_node("/root/InventoryManager")
			inv.clear_inventory()
			var inv_items: Array = player_data.get("inventory", [])
			for i in range(mini(inv_items.size(), inv.DEFAULT_SLOT_COUNT)):
				var item_data = inv_items[i]
				if not item_data.is_empty():
					var qty = item_data.get("quantity", 1)
					inv.add_item(item_data, qty)
					inv.move_item_to_slot(item_data.get("id", ""), i)
					
	if data.has("base"):
		var base_data: Dictionary = data["base"]
		placed_stations = base_data.get("placed_stations", [])
		walls = base_data.get("walls", [])
		storage = base_data.get("storage", [])
		
		if has_node("/root/BuildSystem"):
			var build_sys = get_node("/root/BuildSystem")
			if build_sys.has_method("import_from_world_save_data"):
				build_sys.import_from_world_save_data(self)

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
		var discoveries: Array = data["discoveries"]
		if has_node("/root/DiscoveryLog"):
			var dlog = get_node("/root/DiscoveryLog")
			if dlog.has_method("restore_discoveries"):
				dlog.restore_discoveries(discoveries)
			elif "unlocked_elements" in dlog:
				dlog.unlocked_elements = discoveries.duplicate(true)
