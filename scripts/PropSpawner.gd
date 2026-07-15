class_name PropSpawner
extends Node

const STONE_QUARRY_SCENE_PATH := "res://scenes/StoneQuarry.tscn"
const IRON_MINE_SCENE_PATH := "res://scenes/IronMine.tscn"
const LIMESTONE_MINE_SCENE_PATH := "res://scenes/LimestoneMine.tscn"
const BATTERY_STATION_SCENE_PATH := "res://scenes/BatteryStation.tscn"
const TRAILHEAD_PROP_SCENE_PATH := "res://scenes/TrailheadProp.tscn"
const RUSTED_WARNING_SIGN_SCENE_PATH := "res://scenes/RustedWarningSign.tscn"
const SCORCHED_CRATE_NOTE_SCENE_PATH := "res://scenes/ScorchedCrateNote.tscn"

var host: Node2D
var ground_layer: TileMapLayer
var objects_layer: TileMapLayer
var generated_props: Node2D
var _scene_cache: Dictionary[String, PackedScene] = {}


func configure(owner: Node2D, ground: TileMapLayer, objects: TileMapLayer, props: Node2D) -> void:
	host = owner
	ground_layer = ground
	objects_layer = objects
	generated_props = props


func place_stone_quarry(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 12345
	var coords := Vector2i.ZERO
	for _attempt in range(12):
		coords = Vector2i(rng.randi_range(6, host.MAP_SIZE.x / 4), rng.randi_range(6, host.MAP_SIZE.y / 4))
		if coords.distance_to(host.IRON_MINE_COORDS) >= 7.0:
			break
	_clear_patch(coords, 2, 2)
	_spawn_scene(_get_scene(STONE_QUARRY_SCENE_PATH), coords)


func place_battery_station(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 99999
	var offsets: Array[Vector2i] = [Vector2i(-5, -4), Vector2i(5, -4), Vector2i(-5, 4), Vector2i(5, 4)]
	var coords: Vector2i = host.MAP_SIZE / 2 + offsets[rng.randi_range(0, offsets.size() - 1)]
	_clear_patch(coords, 1, 1)
	_spawn_scene(_get_scene(BATTERY_STATION_SCENE_PATH), coords)


func place_iron_mine() -> void:
	_clear_patch(host.IRON_MINE_COORDS, 1, 1)
	_spawn_scene(_get_scene(IRON_MINE_SCENE_PATH), host.IRON_MINE_COORDS)


func place_limestone_mine() -> void:
	if host._river_tile_coords.is_empty():
		return
	var min_x: int = host.MAP_SIZE.x
	var target_y: int = host.MAP_SIZE.y / 2
	for river_coords: Vector2i in host._river_tile_coords:
		if river_coords.x < min_x:
			min_x = river_coords.x
			target_y = river_coords.y
	var coords := Vector2i(maxi(min_x - 4, 3), target_y)
	_clear_patch(coords, 2, 2)
	_spawn_scene(_get_scene(LIMESTONE_MINE_SCENE_PATH), coords)


func place_overworld_sodium_trailhead() -> void:
	var coords := Vector2i(host.MAP_SIZE.x - 4, host.MAP_SIZE.y / 2)
	_spawn_trailhead(coords, "Sodium Shoals Trailhead", "This route leaves the base behind. Pack dry storage space and return capacity before heading into the shoals.", host.SODIUM_SHOALS_SCENE_PATH, &"arrival_from_overworld", false)


func place_overworld_sulfur_trailhead() -> void:
	var coords: Vector2i = host.OVERWORLD_SULFUR_TRAILHEAD_TILE
	_spawn_trailhead(coords, "Sulfur Flats Trailhead", "This route breaks away from the home map and drops straight into the flats. Bring a distillation kit and room to haul sulfur back.", host.SULFUR_FLATS_SCENE_PATH, &"arrival_from_overworld", false)
	var sign_tile := coords + Vector2i(-5, -3)
	var crate_tile := coords + Vector2i(2, -1)
	_clear_patch(sign_tile, 1, 1)
	_clear_patch(crate_tile, 1, 1)
	_spawn_scene(_get_scene(RUSTED_WARNING_SIGN_SCENE_PATH), sign_tile, Vector2(0.0, -4.0))
	_spawn_scene(_get_scene(SCORCHED_CRATE_NOTE_SCENE_PATH), crate_tile, Vector2(0.0, 2.0))


func place_sodium_return_trailhead() -> void:
	_spawn_trailhead(Vector2i(4, host.MAP_SIZE.y / 2), "Return Trail", "Head back to the home zone. Unstable cargo keeps its risk on the walk out.", host.OVERWORLD_SCENE_PATH, &"from_sodium_shoals", true)


func place_sulfur_return_trailhead() -> void:
	var coords := Vector2i(host.SULFUR_FLATS_ORIGIN.x - 2, host.SULFUR_FLATS_ORIGIN.y + host.SULFUR_FLATS_SIZE.y / 2)
	_spawn_trailhead(coords, "Return Trail", "Head back to the home zone. Unstable cargo keeps its risk on the walk out.", host.OVERWORLD_SCENE_PATH, &"from_sulfur_flats", true)


func place_sodium_contamination_props() -> void:
	var sign_tile: Vector2i = host.SODIUM_SHOALS_ORIGIN + Vector2i(18, 8)
	var crate_tile: Vector2i = host.SODIUM_SHOALS_ORIGIN + Vector2i(20, 10)
	_clear_patch(sign_tile, 1, 1)
	_clear_patch(crate_tile, 1, 1)
	_spawn_scene(_get_scene(RUSTED_WARNING_SIGN_SCENE_PATH), sign_tile, Vector2(0.0, -4.0))
	var crate := _get_scene(SCORCHED_CRATE_NOTE_SCENE_PATH).instantiate()
	crate.set("note_title", "Dumping Manifest")
	crate.set("note_text", "Brine held the sodium waste. Mercury beads settled in the black mud below it. Do not heat the sample drums.")
	crate.set("discovery_entry_id", &"mercury_dumping_warning")
	crate.set("discovery_title", "Shoals Dumping Warning")
	crate.set("discovery_notes", "Industrial dumping left mercury in the Sodium Shoals sediment. Heat and acid exposure can turn carried mercury into toxic vapor.")
	generated_props.add_child(crate)
	crate.position = ground_layer.map_to_local(crate_tile) + Vector2(0.0, 2.0)


func _spawn_trailhead(coords: Vector2i, title: String, blurb: String, target_path: String, entry_id: StringName, returning: bool) -> void:
	_clear_patch(coords, 1, 2)
	var trailhead := _get_scene(TRAILHEAD_PROP_SCENE_PATH).instantiate()
	trailhead.position = ground_layer.map_to_local(coords) + Vector2(0.0, -2.0)
	trailhead.set("trail_name", title)
	trailhead.set("prompt_text", ("Tap Interact to return" if returning else "Tap Interact to travel") if MobileInputRouter.prefers_touch_controls() else ("Press E to return" if returning else "Press E to travel"))
	trailhead.set("travel_blurb", blurb)
	trailhead.set("target_scene_path", target_path)
	trailhead.set("target_entry_point_id", entry_id)
	generated_props.add_child(trailhead)


func _spawn_scene(scene: PackedScene, coords: Vector2i, offset: Vector2 = Vector2.ZERO) -> Node:
	var instance := scene.instantiate()
	instance.position = ground_layer.to_global(ground_layer.map_to_local(coords)) + offset
	generated_props.add_child(instance)
	return instance


func _get_scene(scene_path: String) -> PackedScene:
	var scene := _scene_cache.get(scene_path) as PackedScene
	if scene == null:
		scene = load(scene_path) as PackedScene
		_scene_cache[scene_path] = scene
	return scene


func _clear_patch(center: Vector2i, half_width: int, half_height: int) -> void:
	for y in range(center.y - half_height, center.y + half_height + 1):
		for x in range(center.x - half_width, center.x + half_width + 1):
			var coords := Vector2i(x, y)
			if not bool(host.call("_is_edge", coords)):
				objects_layer.erase_cell(coords)
