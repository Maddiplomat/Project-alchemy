extends Area2D

@export var scan_data: Dictionary = {
	&"composition": [
		{&"element_id": &"iron", &"pct": 0.70},
		{&"element_id": &"charcoal", &"pct": 0.30},
	],
	&"weaknesses": [&"oxidation"],
	&"immunities": [&"physical_blunt"],
}


func _ready() -> void:
	add_to_group(&"enemy")


func get_scan_data() -> Dictionary:
	return scan_data.duplicate(true)
