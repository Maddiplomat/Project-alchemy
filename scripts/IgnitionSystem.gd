extends Node2D

const MIN_IGNITION_DELAY := 8.0
const MAX_IGNITION_DELAY := 15.0

var _ground_layer: TileMapLayer = null
var _ash_tiles: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()
var _ignition_timer: Timer = null


func _ready() -> void:
	_rng.randomize()
	_ignition_timer = Timer.new()
	_ignition_timer.one_shot = true
	_ignition_timer.timeout.connect(_on_ignition_timeout)
	add_child(_ignition_timer)


func configure_zone(ground: TileMapLayer, ash_tiles: Array[Vector2i]) -> void:
	_ground_layer = ground
	_ash_tiles = ash_tiles.duplicate()
	_clear_fire_patches()
	_schedule_next_ignition()


func _on_ignition_timeout() -> void:
	_spawn_random_fire_patch()
	_schedule_next_ignition()


func _spawn_random_fire_patch() -> void:
	if _ground_layer == null or _ash_tiles.is_empty():
		return

	var candidate_tiles := _ash_tiles.duplicate()
	candidate_tiles.shuffle()
	var player_tile := _get_player_tile()

	for coords: Vector2i in candidate_tiles:
		if coords == player_tile:
			continue
		if _has_fire_patch_at(coords):
			continue

		var fire_patch := ObjectPool.get_instance_by_id(ObjectPool.SCENE_FIRE_PATCH)
		if fire_patch == null:
			return
		fire_patch.set_meta(&"tile_coords", coords)
		add_child(fire_patch)
		fire_patch.global_position = _ground_layer.to_global(_ground_layer.map_to_local(coords))
		return


func _schedule_next_ignition() -> void:
	if _ignition_timer == null:
		return
	if _ash_tiles.is_empty():
		_ignition_timer.stop()
		return
	_ignition_timer.start(_rng.randf_range(MIN_IGNITION_DELAY, MAX_IGNITION_DELAY))


func _get_player_tile() -> Vector2i:
	if _ground_layer == null:
		return Vector2i(-9999, -9999)
	var player := GameManager.get_player()
	if not (player is Node2D):
		return Vector2i(-9999, -9999)
	return _ground_layer.local_to_map(_ground_layer.to_local((player as Node2D).global_position))


func _has_fire_patch_at(coords: Vector2i) -> bool:
	for child in get_children():
		if child is Timer:
			continue
		if child.has_meta(&"tile_coords") and child.get_meta(&"tile_coords") == coords:
			return true
	return false


func _clear_fire_patches() -> void:
	for child in get_children():
		if child is Timer:
			continue
		ObjectPool.release(child)
