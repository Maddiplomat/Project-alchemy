class_name DebugLog
extends RefCounted


static func info(message: String) -> void:
	if not _should_log():
		return
	print_verbose(message)


static func warning(message: String) -> void:
	if not _should_log():
		return
	push_warning(message)


static func _should_log() -> bool:
	return OS.is_debug_build() or OS.has_feature("editor")
