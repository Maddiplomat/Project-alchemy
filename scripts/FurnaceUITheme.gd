class_name FurnaceUITheme
extends Resource

@export_category("Panel")
@export var panel_view_scale := 0.46
@export var panel_margin := Vector2(24.0, 24.0)
@export var touch_panel_margin := 16.0
@export var panel_background := Color(0.10, 0.11, 0.13, 0.96)
@export var panel_border := Color(0.28, 0.30, 0.34, 1.0)

@export_category("Slots and controls")
@export var slot_background := Color(0.14, 0.16, 0.19, 1.0)
@export var slot_border := Color(0.34, 0.37, 0.41, 1.0)
@export var slot_empty := Color(0.52, 0.55, 0.60, 1.0)
@export var output_preview := Color(0.58, 0.61, 0.66, 1.0)
@export var button_idle := Color(0.28, 0.30, 0.35, 1.0)
@export var smelt_button := Color(0.79, 0.47, 0.18, 1.0)
@export var forge_button := Color(0.39, 0.54, 0.74, 1.0)

@export_category("Temperature")
@export var gauge_normal := Color(0.95, 0.62, 0.22, 1.0)
@export var gauge_danger := Color(0.89, 0.29, 0.24, 1.0)
@export var carbonisation_good := Color(0.34, 0.82, 0.45, 1.0)
@export var carbonisation_slag := Color(0.89, 0.29, 0.24, 1.0)

@export_category("Ratio guide")
@export var ratio_guide_background := Color(0.18, 0.20, 0.23, 0.82)
@export var ratio_iron_fill := Color(0.34, 0.44, 0.52, 0.92)
@export var ratio_carbon_fill := Color(0.54, 0.31, 0.12, 0.96)
@export var ratio_target_zone := Color(0.34, 0.82, 0.45, 0.32)
@export var ratio_current_marker := Color(0.97, 0.97, 0.97, 0.95)
