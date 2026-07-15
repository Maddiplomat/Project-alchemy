extends Node

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const SODIUM_SHOALS_SCENE_PATH := "res://scenes/SodiumShoals.tscn"
const SULFUR_FLATS_SCENE_PATH := "res://scenes/SulfurFlats.tscn"

var _failures := 0
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
	await _run()
	_scene_tree.quit(1 if _failures > 0 else 0)


func _run() -> void:
	await _assert_travel_entry(SODIUM_SHOALS_SCENE_PATH, &"arrival_from_overworld")
	await _assert_travel_entry(SULFUR_FLATS_SCENE_PATH, &"arrival_from_overworld")
	if _failures == 0:
		print("BiomeTravelEntryTest passed.")


func _assert_travel_entry(target_scene_path: String, entry_point_id: StringName) -> void:
	if EventBus.get_world_system() != null and EventBus.get_world_system().has_method("clear_persistent_state"):
		EventBus.get_world_system().clear_persistent_state()
	if GameManager != null:
		GameManager.start_new_game()
	await _change_scene_and_wait(WORLD_SCENE_PATH)

	var travel_started := bool(EventBus.get_world_system().travel_to_scene(target_scene_path, entry_point_id))
	_assert(travel_started, "Expected travel to start for %s." % target_scene_path)
	if not travel_started:
		return
	await _wait_for_scene(target_scene_path)

	var current_scene := get_tree().current_scene
	var player := GameManager.get_player()
	_assert(current_scene != null, "Expected a current scene after traveling to %s." % target_scene_path)
	_assert(player != null, "Expected the player to stay registered after traveling to %s." % target_scene_path)
	if current_scene == null or player == null:
		return

	var travel_entries := current_scene.get_node_or_null("TravelEntries") as Node2D
	_assert(travel_entries != null, "Expected %s to define TravelEntries." % target_scene_path)
	if travel_entries == null:
		return
	var marker := travel_entries.get_node_or_null(String(entry_point_id)) as Node2D
	_assert(marker != null, "Expected travel entry %s in %s." % [entry_point_id, target_scene_path])
	if marker == null:
		return

	_assert(
		player.global_position.distance_to(marker.global_position) <= 0.1,
		"Expected player to land at %s in %s, got %s instead of %s."
			% [entry_point_id, target_scene_path, player.global_position, marker.global_position]
	)


func _change_scene_and_wait(scene_path: String) -> void:
	var scene_error := _scene_tree.change_scene_to_file(scene_path)
	_assert(scene_error == OK, "Expected to change to %s." % scene_path)
	if scene_error != OK:
		return
	await _wait_for_scene(scene_path)


func _wait_for_scene(scene_path: String) -> void:
	var timeout_frames := 24
	while timeout_frames > 0:
		await _scene_tree.process_frame
		var current_scene := _scene_tree.current_scene
		if current_scene != null and str(current_scene.scene_file_path) == scene_path:
			await _scene_tree.process_frame
			return
		timeout_frames -= 1
	_assert(false, "Timed out waiting for scene %s to load." % scene_path)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
