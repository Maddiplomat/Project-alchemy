class_name ItemSlot
extends PanelContainer

@export var item_icon: Texture2D:
	set(value):
		item_icon = value
		_apply_content()
@export var item_name := "Empty":
	set(value):
		item_name = value
		_apply_content()
@export var quantity := 0:
	set(value):
		quantity = value
		_apply_content()

@onready var icon: TextureRect = $Margin/Content/Icon
@onready var name_label: Label = $Margin/Content/Name
@onready var quantity_label: Label = $Margin/Content/Quantity


func _ready() -> void:
	_apply_content()


func configure(icon_texture: Texture2D, display_name: String, item_quantity: int) -> void:
	item_icon = icon_texture
	item_name = display_name
	quantity = item_quantity
	_apply_content()


func _apply_content() -> void:
	if not is_node_ready():
		return
	icon.texture = item_icon
	name_label.text = item_name
	quantity_label.text = "x%d" % quantity if quantity > 0 else ""
