class_name DamageNumber
extends Label

const LIFETIME := 0.8
const RISE_DISTANCE := 24.0
const DAMAGE_COLORS := {
	&"physical_sharp": Color.WHITE,
	&"oxidation": Color(0.937, 0.624, 0.153, 1.0),
	&"electrical": Color(0.365, 0.792, 0.647, 1.0),
	&"immune": Color(0.25, 0.25, 0.25, 1.0),
}

var _tween: Tween = null

func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func setup(amount: float, damage_type: StringName) -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	var is_immune := amount <= 0.0 or damage_type == &"immune"
	text = "IMMUNE" if is_immune else str(int(round(amount)))
	modulate = DAMAGE_COLORS.get(&"immune" if is_immune else damage_type, Color.WHITE)
	modulate.a = 1.0

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "global_position:y", global_position.y - RISE_DISTANCE, LIFETIME)
	_tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	_tween.finished.connect(_release_to_pool, CONNECT_ONE_SHOT)


func _pool_reset() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	text = ""
	modulate = Color.WHITE


func _release_to_pool() -> void:
	ObjectPool.release(self)
