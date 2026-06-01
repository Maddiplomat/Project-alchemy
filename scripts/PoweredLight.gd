extends PointLight2D

var _base_grid: Node = null


func _ready() -> void:
	_base_grid = get_node_or_null("/root/BaseGrid")
	if _base_grid == null:
		energy = 0.0
		return

	energy = 0.8 if _base_grid.is_powered() else 0.0

	if _base_grid.has_signal("power_activated"):
		_base_grid.power_activated.connect(_on_power_activated)
	if _base_grid.has_signal("power_deactivated"):
		_base_grid.power_deactivated.connect(_on_power_deactivated)


func _on_power_activated() -> void:
	energy = 0.8


func _on_power_deactivated() -> void:
	energy = 0.0
