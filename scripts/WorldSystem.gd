extends Node
# Autoload: WorldSystem

var _current_seed: int = 0


func get_seed() -> int:
	return _current_seed


func set_seed(value: int) -> void:
	_current_seed = value


func generate_seed() -> int:
	_current_seed = randi()
	return _current_seed
