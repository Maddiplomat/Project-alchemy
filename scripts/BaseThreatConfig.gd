class_name BaseThreatConfig
extends Resource

@export_category("Scheduling")
@export var check_interval_seconds: float = 1.0
@export var volatile_check_seconds: float = 1.5
@export var breach_report_cooldown_seconds: float = 4.0

@export_category("Weather Pressure")
@export var exposed_storage_damage_seconds: float = 12.0
@export var rain_storage_purity_loss: float = 0.25
@export var rain_storage_lithium_charge_loss: float = 0.35
@export var rain_station_warning_seconds: float = 5.0
@export var wet_status_refresh_seconds: float = 3.0

@export_category("Storage and Enclosure")
@export var volatile_danger_distance_pixels: float = 72.0
@export var volatile_safe_distance_pixels: float = 128.0
@export var enclosure_radius_tiles: int = 5

@export_category("Night Escalation")
@export var night_attraction_radius_pixels: float = 300.0
@export var escalation_day_tier_one: int = 3
@export var escalation_day_tier_two: int = 5
@export var night_attraction_radius_tier_one_pixels: float = 380.0
@export var night_attraction_radius_tier_two_pixels: float = 440.0
