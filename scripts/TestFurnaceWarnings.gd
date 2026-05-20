extends Node2D

@export var test_temperature := 0.0
@export var input_a_id: StringName = &""
@export var input_a_quantity := 0
@export var input_b_id: StringName = &""
@export var input_b_quantity := 0
@export var auto_smelt := false

@onready var furnace := $Furnace

var _inputs_applied := false
var smelt_executed := false
var last_smelt_result: Dictionary = {}


func _ready() -> void:
	_apply_inputs()
	_apply_temperature()
	if auto_smelt:
		call_deferred("_run_auto_smelt")
	else:
		call_deferred("_report_warning_state")


func _physics_process(_delta: float) -> void:
	_apply_inputs()
	_apply_temperature()


func _apply_inputs() -> void:
	if _inputs_applied or furnace == null:
		return

	if input_a_quantity > 0 and not input_a_id.is_empty():
		furnace.set_input(&"input_a", input_a_id, input_a_quantity)
	if input_b_quantity > 0 and not input_b_id.is_empty():
		furnace.set_input(&"input_b", input_b_id, input_b_quantity)
	_inputs_applied = true


func _apply_temperature() -> void:
	if furnace == null:
		return

	furnace.current_temp = test_temperature
	furnace.target_temp = test_temperature
	furnace.fuel_level = 0.0
	furnace.fuel_rate = 0.0
	furnace.temp_changed.emit(test_temperature)


func _run_auto_smelt() -> void:
	if smelt_executed:
		return

	await get_tree().process_frame
	await get_tree().process_frame

	var furnace_ui := get_tree().current_scene.find_child("FurnaceUI", true, false)
	if furnace_ui == null or not furnace_ui.has_method("_evaluate_smelt_request"):
		return

	_sync_furnace_ui(furnace_ui)
	furnace_ui._evaluate_smelt_request()
	last_smelt_result = furnace_ui._last_reaction_result.duplicate(true)
	smelt_executed = true
	_sync_furnace_ui(furnace_ui)
	_print_warning_state(furnace_ui)


func _report_warning_state() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var furnace_ui := get_tree().current_scene.find_child("FurnaceUI", true, false)
	if furnace_ui == null:
		return

	_sync_furnace_ui(furnace_ui)
	_print_warning_state(furnace_ui)


func _print_warning_state(furnace_ui: Node) -> void:
	print(
		"[TestFurnaceWarnings] temp=%.1f mode=%s flash=%s sfx=%s flash_threshold=%.1f sfx_threshold=%.1f result_threshold=%.1f audio_count=%d last_audio_temp=%.1f display=%s smelt_executed=%s result=%s"
		% [
			test_temperature,
			str(furnace_ui.warning_mode),
			str(furnace_ui.warning_flash_active),
			str(furnace_ui.warning_sfx_fired),
			float(furnace_ui.warning_flash_threshold),
			float(furnace_ui.warning_sfx_threshold),
			float(furnace_ui.warning_result_threshold),
			int(furnace_ui.warning_audio_play_count),
			float(furnace_ui.warning_last_audio_temp),
			str(furnace_ui.warning_display_text),
			str(smelt_executed),
			JSON.stringify(last_smelt_result),
		]
	)


func _sync_furnace_ui(furnace_ui: Node) -> void:
	_apply_temperature()
	if furnace_ui.has_method("_pull_state_from_furnace"):
		furnace_ui._pull_state_from_furnace()
