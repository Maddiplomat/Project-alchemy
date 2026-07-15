class_name WorldGenConfig
extends Resource

@export_category("Terrain")
@export var noise_frequency: float = 0.08
@export_range(0.0, 1.0, 0.01) var sparse_tree_density: float = 0.20

@export_category("Trees")
@export var harvestable_tree_count: int = 20
@export var tree_respawn_seconds: float = 600.0
@export var tree_respawn_retry_seconds: float = 30.0

@export_category("Overworld Resources")
@export var iron_hills_lithium_size := Vector2i(10, 9)
@export var sulfur_spawn_min: int = 8
@export var sulfur_spawn_max: int = 12
@export var lithium_spawn_min: int = 5
@export var lithium_spawn_max: int = 6
@export var water_respawn_seconds: float = 120.0
@export var lithium_respawn_seconds: float = 210.0

@export_category("Biome Resources")
@export var sodium_spawn_min: int = 8
@export var sodium_spawn_max: int = 12
@export var mercury_spawn_min: int = 3
@export var mercury_spawn_max: int = 5

@export_category("Biome Movement")
@export var sulfur_flats_cracked_speed_multiplier: float = 0.7
@export var sodium_shoals_brine_speed_multiplier: float = 0.84
