extends Node

const EDITOR_RUNTIME_PATH := "res://addons/godot_mcp/runtime/mcp_runtime.gd"

var _editor_runtime: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _should_start_editor_runtime():
		set_process(false)
		return
	if not ResourceLoader.exists(EDITOR_RUNTIME_PATH):
		set_process(false)
		return
	var runtime_script := load(EDITOR_RUNTIME_PATH)
	if runtime_script == null:
		set_process(false)
		return
	_editor_runtime = runtime_script.new()
	if _editor_runtime == null:
		set_process(false)
		return
	_editor_runtime.name = "EditorMCPRuntime"
	add_child(_editor_runtime)


func push_runtime_log(level: String, message: String) -> void:
	if _editor_runtime != null and _editor_runtime.has_method("push_runtime_log"):
		_editor_runtime.push_runtime_log(level, message)


func _should_start_editor_runtime() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return OS.has_feature("editor")
