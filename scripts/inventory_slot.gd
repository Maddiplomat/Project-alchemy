extends Panel

signal drag_started(slot_index: int)
signal drag_released(slot_index: int)
signal hover_started(slot_index: int)
signal hover_ended(slot_index: int)

@onready var item_icon: TextureRect = $ItemIcon
@onready var quantity_label: Label = $QuantityLabel

var slot_index := -1
var current_item_id := ""
var current_quantity := 0
var current_purity := 0.0
var is_drag_origin := false
var _placeholder_textures := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_started.emit(slot_index)
		else:
			drag_released.emit(slot_index)
		accept_event()

func update_slot(item_id: String, quantity: int, purity: float) -> void:
	current_item_id = item_id
	current_quantity = quantity
	current_purity = purity
	is_drag_origin = false
	
	if quantity > 0:
		item_icon.texture = _get_placeholder_texture(item_id)
		item_icon.modulate = _get_item_color(item_id)
		quantity_label.text = str(quantity)
	else:
		current_item_id = ""
	
	_apply_visual_state()

func clear() -> void:
	current_item_id = ""
	current_quantity = 0
	current_purity = 0.0
	is_drag_origin = false
	_apply_visual_state()

func has_item() -> bool:
	return current_item_id != "" and current_quantity > 0

func set_drag_origin(active: bool) -> void:
	is_drag_origin = active
	_apply_visual_state()

func _apply_visual_state() -> void:
	var has_stack := has_item()
	item_icon.visible = has_stack and not is_drag_origin
	quantity_label.visible = has_stack and not is_drag_origin
	
	if has_stack:
		item_icon.texture = _get_placeholder_texture(current_item_id)
		item_icon.modulate = _get_item_color(current_item_id)
		quantity_label.text = str(current_quantity)
	else:
		item_icon.texture = null
		quantity_label.text = ""

func _on_mouse_entered() -> void:
	hover_started.emit(slot_index)

func _on_mouse_exited() -> void:
	hover_ended.emit(slot_index)

func _get_item_color(item_id: String) -> Color:
	match item_id:
		"wood":
			return Color.BURLYWOOD
		"stone":
			return Color.GRAY
		"iron":
			return Color.SILVER
		_:
			return Color.WHITE

func _get_placeholder_texture(item_id: String) -> Texture2D:
	if _placeholder_textures.has(item_id):
		return _placeholder_textures[item_id]
	
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.WHITE)
	
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	_placeholder_textures[item_id] = texture
	return texture
