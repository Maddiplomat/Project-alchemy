extends Node
# Autoload: WorldSystem

const PERSISTENCE_KEY := &"world_system"
const TRAVEL_CONTEXT_KEY := &"__travel_context"

var _current_seed: int = 0
var _scene_seeds: Dictionary[String, int] = {}
var _scene_state_by_path: Dictionary[String, Dictionary] = {}
var _pending_restore_state: Dictionary = {}
var _pending_travel_context: Dictionary = {}


func _ready() -> void:
	if GameManager != null and GameManager.has_signal("new_game_started"):
		if not GameManager.new_game_started.is_connected(_on_new_game_started):
			GameManager.new_game_started.connect(_on_new_game_started)


func get_seed() -> int:
	return _current_seed


func get_persistence_key() -> StringName:
	return PERSISTENCE_KEY


func set_seed(value: int) -> void:
	_current_seed = value


func get_seed_for_scene(scene_path: String) -> int:
	if scene_path.is_empty():
		return _current_seed
	if not _scene_seeds.has(scene_path):
		_scene_seeds[scene_path] = int(hash("%d:%s" % [_current_seed, scene_path]))
	return _scene_seeds[scene_path]


func set_seed_for_scene(scene_path: String, value: int) -> void:
	if scene_path.is_empty():
		_current_seed = value
		return
	_scene_seeds[scene_path] = value


func generate_seed() -> int:
	_current_seed = randi()
	_scene_seeds.clear()
	return _current_seed


func capture_persistent_state() -> Dictionary:
	return {
		"current_seed": _current_seed,
		"scene_seeds": _scene_seeds.duplicate(true),
		"scene_state_by_path": _scene_state_by_path.duplicate(true),
	}


func restore_persistent_state(data: Dictionary) -> void:
	clear_persistent_state()
	if data.is_empty():
		return
	_current_seed = int(data.get("current_seed", 0))
	for raw_scene_path in (data.get("scene_seeds", {}) as Dictionary).keys():
		var scene_path := str(raw_scene_path)
		if scene_path.is_empty():
			continue
		_scene_seeds[scene_path] = int((data.get("scene_seeds", {}) as Dictionary).get(raw_scene_path, 0))
	for raw_scene_path in (data.get("scene_state_by_path", {}) as Dictionary).keys():
		var scene_path := str(raw_scene_path)
		if scene_path.is_empty():
			continue
		var scene_state: Variant = (data.get("scene_state_by_path", {}) as Dictionary).get(raw_scene_path, {})
		if scene_state is Dictionary:
			_scene_state_by_path[scene_path] = (scene_state as Dictionary).duplicate(true)


func clear_persistent_state() -> void:
	_current_seed = 0
	_scene_seeds.clear()
	_scene_state_by_path.clear()
	_pending_restore_state.clear()
	_pending_travel_context.clear()


func store_scene_state(scene_path: String, scene_state: Dictionary) -> void:
	if scene_path.is_empty() or scene_state.is_empty():
		return
	_scene_state_by_path[scene_path] = scene_state.duplicate(true)


func get_scene_state(scene_path: String) -> Dictionary:
	if scene_path.is_empty():
		return {}
	return (_scene_state_by_path.get(scene_path, {}) as Dictionary).duplicate(true)


func travel_to_scene(target_scene_path: String, entry_point_id: StringName = &"") -> bool:
	if target_scene_path.is_empty():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var current_scene := tree.current_scene
	if current_scene == null:
		return false
	var current_scene_path := str(current_scene.scene_file_path)
	if current_scene_path.is_empty():
		return false

	var world_save_data := EventBus.get_world_save_data()
	if world_save_data == null or not world_save_data.has_method("capture_runtime_state"):
		return false
	var source_envelope: Dictionary = world_save_data.capture_runtime_state()
	var source_state: Dictionary = (source_envelope.get("current_scene_state", {}) as Dictionary).duplicate(true)
	if source_state.is_empty():
		return false
	store_scene_state(current_scene_path, source_state)

	var target_state := get_scene_state(target_scene_path)
	var travel_context := {
		&"target_scene_path": target_scene_path,
		&"entry_point_id": entry_point_id,
		&"use_entry_point": target_state.is_empty(),
	}
	_pending_restore_state = _compose_travel_restore_state(source_state, target_state, target_scene_path)
	_pending_restore_state[String(TRAVEL_CONTEXT_KEY)] = travel_context.duplicate(true)
	_pending_travel_context = travel_context
	return tree.change_scene_to_file(target_scene_path) == OK


func consume_pending_restore_state() -> Dictionary:
	var state := _pending_restore_state.duplicate(true)
	_pending_restore_state.clear()
	return state


func consume_pending_travel_context() -> Dictionary:
	var context := _pending_travel_context.duplicate(true)
	_pending_travel_context.clear()
	return context


func queue_pending_restore_state(restore_state: Dictionary, travel_context: Dictionary = {}) -> void:
	_pending_restore_state = restore_state.duplicate(true)
	if not travel_context.is_empty():
		_pending_restore_state[String(TRAVEL_CONTEXT_KEY)] = travel_context.duplicate(true)
	_pending_travel_context = travel_context.duplicate(true)


func has_pending_restore_state() -> bool:
	return not _pending_restore_state.is_empty() or not _pending_travel_context.is_empty()


func _compose_travel_restore_state(source_state: Dictionary, target_state: Dictionary, target_scene_path: String) -> Dictionary:
	var merged := source_state.duplicate(true)
	var player_state: Dictionary = (merged.get("player", {}) as Dictionary).duplicate(true)
	player_state["active_path"] = target_scene_path
	merged["player"] = player_state

	if target_state.is_empty():
		merged["world"] = {
			"seed": str(get_seed_for_scene(target_scene_path)),
			"biomes_unlocked": ((source_state.get("world", {}) as Dictionary).get("biomes_unlocked", []) as Array).duplicate(true),
			"explored_tiles": [],
		}
		merged["base"] = {
			"placed_stations": [],
			"walls": [],
			"storage": [],
			"chest_inventories": {},
			"defense_grid_charge": 0.0,
		}
		merged["resources"] = {
			"active_trees": [],
			"pending_tree_respawns": [],
		}
		return merged

	var target_player_state := (target_state.get("player", {}) as Dictionary).duplicate(true)
	player_state["position"] = (target_player_state.get("position", player_state.get("position", {"x": 0.0, "y": 0.0})) as Dictionary).duplicate(true)
	merged["player"] = player_state
	merged["world"] = ((target_state.get("world", {}) as Dictionary)).duplicate(true)
	merged["base"] = ((target_state.get("base", {}) as Dictionary)).duplicate(true)
	merged["resources"] = ((target_state.get("resources", {}) as Dictionary)).duplicate(true)
	return merged


func _on_new_game_started() -> void:
	if has_pending_restore_state():
		return
	clear_persistent_state()
