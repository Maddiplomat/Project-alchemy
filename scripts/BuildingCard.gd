class_name BuildingCard
extends PanelContainer

@export var building_icon: Texture2D:
	set(value):
		building_icon = value
		_apply_content()
@export var building_name := "":
	set(value):
		building_name = value
		_apply_content()
@export var building_meta := "":
	set(value):
		building_meta = value
		_apply_content()

@onready var icon: TextureRect = $Margin/VBox/Icon
@onready var name_label: Label = $Margin/VBox/Name
@onready var meta_label: Label = $Margin/VBox/Meta


func _ready() -> void:
	_apply_content()


func configure(icon_texture: Texture2D, display_name: String, meta: String) -> void:
	building_icon = icon_texture
	building_name = display_name
	building_meta = meta
	_apply_content()


func _apply_content() -> void:
	if not is_node_ready():
		return
	icon.texture = building_icon
	name_label.text = building_name
	meta_label.text = building_meta
