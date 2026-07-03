extends Node

signal markers_changed
signal marker_added(marker_id: StringName, marker: Dictionary)
signal marker_removed(marker_id: StringName)

const HOME_MARKER_ID := &"home"
const SULFUR_FLATS_MARKER_ID := &"sulfur_flats"
const DEATH_MARKER_ID := &"death"

var markers: Dictionary[StringName, Dictionary] = {}

var _bound_player: Node2D = null
var _bound_world: Node = null
var _sulfur_marker_discovered := false
var _sulfur_marker_position := Vector2.ZERO
var _has_sulfur_marker_position := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.register_service(EventBus.SERVICE_MAP_MARKERS, self)
	if GameManager != null:
		GameManager.player_died.connect(_on_player_died)
		GameManager.game_state_changed.connect(_on_game_state_changed)
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
	call_deferred("_refresh_world_bindings")


func _exit_tree() -> void:
	EventBus.unregister_service(EventBus.SERVICE_MAP_MARKERS, self)


func _process(_delta: float) -> void:
	_refresh_world_bindings()
	_update_sulfur_flats_marker()


func get_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker_id: StringName in markers.keys():
		result.append((markers[marker_id] as Dictionary).duplicate(true))
	return result


func get_markers_by_type(marker_type: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker: Dictionary in get_markers():
		if StringName(marker.get(&"type", &"")) == marker_type:
			result.append(marker)
	return result


func get_player_world_position() -> Vector2:
	if _bound_player != null and is_instance_valid(_bound_player):
		return _bound_player.global_position
	return Vector2.ZERO


func clear_death_marker() -> void:
	_remove_marker(DEATH_MARKER_ID)


func get_world_rect() -> Rect2:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return Rect2()
	var ground: TileMapLayer = current_scene.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return Rect2()
	var used_rect: Rect2i = ground.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return Rect2()
	var top_left: Vector2 = ground.to_global(ground.map_to_local(used_rect.position))
	var bottom_right: Vector2 = ground.to_global(ground.map_to_local(used_rect.end))
	return Rect2(top_left, bottom_right - top_left)


func _on_tree_node_added(node: Node) -> void:
	if node == null:
		return
	if node == GameManager.get_player():
		call_deferred("_refresh_world_bindings")
		return
	if node.has_node("Ground"):
		call_deferred("_refresh_world_bindings")
		return
	if node is Node2D:
		call_deferred("_bind_mining_node_by_id", node.get_instance_id())


func _refresh_world_bindings() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return

	if _bound_world != current_scene:
		_bound_world = current_scene
		_has_sulfur_marker_position = false
		_sulfur_marker_discovered = markers.has(SULFUR_FLATS_MARKER_ID)
		_bind_world_nodes(current_scene)
		_refresh_sulfur_marker_for_world()

	if (_bound_player == null or not is_instance_valid(_bound_player)):
		var player := GameManager.get_player()
		if player != null:
			_bound_player = player
			_set_marker(HOME_MARKER_ID, {
				&"id": HOME_MARKER_ID,
				&"type": &"home",
				&"title": "Home",
				&"world_position": player.global_position,
			})


func _bind_world_nodes(world_root: Node) -> void:
	for node in world_root.find_children("*", "", true, false):
		if node is Node2D:
			_bind_mining_node(node as Node2D)
	_bind_sulfur_zone(world_root)


func _bind_mining_node(node: Node) -> void:
	var node_2d := node as Node2D
	if node_2d == null:
		return
	if node_2d.has_meta(&"map_markers_bound"):
		return

	var signal_name: String = ""
	var title: String = ""
	if node_2d.has_signal("stone_mined"):
		signal_name = "stone_mined"
		title = "Stone Quarry"
	elif node_2d.has_signal("iron_mined"):
		signal_name = "iron_mined"
		title = "Iron Mine"
	elif node_2d.has_signal("limestone_mined"):
		signal_name = "limestone_mined"
		title = "Limestone Mine"

	if signal_name.is_empty():
		return

	node_2d.set_meta(&"map_markers_bound", true)
	node_2d.connect(signal_name, Callable(self, "_on_mining_node_interacted").bind(node_2d.global_position, StringName(title.to_snake_case()), title))


func _bind_mining_node_by_id(node_id: int) -> void:
	if node_id <= 0:
		return
	var node := instance_from_id(node_id) as Node
	if node == null or not is_instance_valid(node):
		return
	_bind_mining_node(node)


func _bind_sulfur_zone(world_root: Node) -> void:
	if world_root == null:
		return
	if _has_sulfur_marker_position:
		return
	var world_gen: Node = world_root as Node
	if world_gen == null:
		return
	if not world_gen.has_method("get_sulfur_flats_marker_position"):
		return
	var marker_position := world_gen.call("get_sulfur_flats_marker_position") as Vector2
	if marker_position == Vector2.ZERO:
		return
	_sulfur_marker_position = marker_position
	_has_sulfur_marker_position = true


func _update_sulfur_flats_marker() -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		return
	if _sulfur_marker_discovered:
		_refresh_sulfur_marker_for_world()
		return
	if not _is_player_in_sulfur_flats():
		return

	_sulfur_marker_discovered = true
	_set_marker(SULFUR_FLATS_MARKER_ID, {
		&"id": SULFUR_FLATS_MARKER_ID,
		&"type": &"sulfur_flats",
		&"title": "Sulfur Flats",
		&"world_position": _get_sulfur_marker_position(),
	})


func _is_player_in_sulfur_flats() -> bool:
	if _bound_world == null:
		return false
	if _bound_world.has_method("is_sulfur_flats_scene") and bool(_bound_world.call("is_sulfur_flats_scene")):
		return true
	if _bound_world.has_method("is_sulfur_flats_at_world_position"):
		return bool(_bound_world.call("is_sulfur_flats_at_world_position", _bound_player.global_position))
	return false


func _get_sulfur_marker_position() -> Vector2:
	if _has_sulfur_marker_position:
		return _sulfur_marker_position
	return _bound_player.global_position


func _refresh_sulfur_marker_for_world() -> void:
	if not _sulfur_marker_discovered:
		return
	if not _has_sulfur_marker_position:
		return
	if not markers.has(SULFUR_FLATS_MARKER_ID):
		return
	var marker := (markers[SULFUR_FLATS_MARKER_ID] as Dictionary).duplicate(true)
	var world_position := _get_sulfur_marker_position()
	if marker.get(&"world_position", Vector2.ZERO) == world_position:
		return
	marker[&"world_position"] = world_position
	_set_marker(SULFUR_FLATS_MARKER_ID, marker)


func _on_mining_node_interacted(_amount: int, world_position: Vector2, marker_id: StringName, title: String) -> void:
	if markers.has(marker_id):
		return
	_set_marker(marker_id, {
		&"id": marker_id,
		&"type": &"mine",
		&"title": title,
		&"world_position": world_position,
	})


func _on_player_died(_cause_of_death: StringName) -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		return
	_set_marker(DEATH_MARKER_ID, {
		&"id": DEATH_MARKER_ID,
		&"type": &"death",
		&"title": "Death",
		&"world_position": _bound_player.global_position,
	})


func _on_game_state_changed(_previous_state: int, new_state: int) -> void:
	if new_state == GameManager.GameState.PLAYING:
		clear_death_marker()


func _set_marker(marker_id: StringName, marker: Dictionary) -> void:
	var existed: bool = markers.has(marker_id)
	markers[marker_id] = marker.duplicate(true)
	markers_changed.emit()
	if not existed:
		marker_added.emit(marker_id, (markers[marker_id] as Dictionary).duplicate(true))


func _remove_marker(marker_id: StringName) -> void:
	if not markers.has(marker_id):
		return
	markers.erase(marker_id)
	markers_changed.emit()
	marker_removed.emit(marker_id)
