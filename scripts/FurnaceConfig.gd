class_name FurnaceConfig
extends Resource

@export_category("Temperature")
@export var max_temperature: float = 2000.0
@export var smelting_min_temperature: float = 1200.0
@export var danger_temperature: float = 1600.0
@export var carbonisation_optimal_min: float = 400.0
@export var carbonisation_slag_temperature: float = 700.0
@export var carbonisation_flash_temperature: float = 650.0
@export var carbonisation_sfx_temperature: float = 680.0
@export var smelting_flash_temperature: float = 1500.0
@export var smelting_sfx_temperature: float = 1580.0

@export_category("Explosion")
@export var explosion_radius: float = 32.0
@export var explosion_damage: int = 35
@export var explosion_shake_strength: float = 1.2
@export var explosion_shake_duration: float = 0.6
@export var explosion_spark_count: int = 80
@export var explosion_spark_lifetime: float = 0.4
@export_range(0.0, 1.0, 0.01) var explosion_slot_loss_chance: float = 0.5

@export_category("Warning FX")
@export var warning_flash_speed: float = 0.014
