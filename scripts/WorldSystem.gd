extends Node

const DEFAULT_SEED := 1337

var current_seed: int = DEFAULT_SEED


func set_seed(seed: int) -> void:
	current_seed = seed


func get_seed() -> int:
	return current_seed
