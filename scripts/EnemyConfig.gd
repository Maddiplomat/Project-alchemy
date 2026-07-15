class_name EnemyConfig
extends Resource

@export_category("Core")
@export var health: int = 100
@export var resistances: Dictionary = {}

@export_category("Movement")
@export var move_speed: float = 60.0
@export var night_move_speed: float = 80.0
@export var burrow_speed: float = 0.0
@export var night_burrow_speed: float = 0.0
@export var patrol_radius: float = 96.0
@export var patrol_wait_seconds: float = 1.5
@export var max_pursuit_radius: float = 0.0

@export_category("Detection and Attack")
@export var detection_radius: float = 180.0
@export var night_detection_multiplier: float = 1.5
@export var attack_range: float = 48.0
@export var attack_cooldown_seconds: float = 0.8
@export var attack_damage: int = 12
@export var scanner_alert_radius: float = 150.0
@export var chase_repath_interval: float = 0.3
@export var leash_seconds: float = 10.0

@export_category("Crawler Behaviour")
@export var reburrow_radius: float = 0.0
@export var player_emerge_offset: float = 24.0
@export var min_attack_separation: float = 18.0
@export var emerge_warning_seconds: float = 2.0

@export_category("Presentation")
@export var health_bar_hide_delay: float = 2.0
@export var health_bar_full_color := Color(0.31, 0.82, 0.38, 1.0)
@export var health_bar_mid_color := Color(0.91, 0.79, 0.23, 1.0)
@export var health_bar_low_color := Color(0.86, 0.24, 0.22, 1.0)
@export var alert_indicator_offset := Vector2(0.0, -48.0)
@export var alert_indicator_duration: float = 1.5
