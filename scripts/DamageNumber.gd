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


func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func setup(amount: float, damage_type: StringName) -> void:
	var is_immune := amount <= 0.0 or damage_type == &"immune"
	text = "IMMUNE" if is_immune else str(int(round(amount)))
	modulate = DAMAGE_COLORS.get(&"immune" if is_immune else damage_type, Color.WHITE)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position:y", global_position.y - RISE_DISTANCE, LIFETIME)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tween.finished.connect(queue_free)
