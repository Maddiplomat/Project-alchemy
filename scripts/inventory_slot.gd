extends Panel

signal drag_started(slot_index: int)
signal drag_released(slot_index: int)
signal clicked(slot_index: int)
signal hover_started(slot_index: int)
signal hover_ended(slot_index: int)

@onready var item_icon: TextureRect = $ItemIcon
@onready var broken_overlay: Control = $BrokenOverlay
@onready var durability_bar_background: ColorRect = $DurabilityBarBackground
@onready var durability_bar_fill: ColorRect = $DurabilityBarBackground/DurabilityBarFill
@onready var quantity_label: Label = $QuantityLabel

const DURABILITY_HIGH_COLOR := Color(0.45, 0.83, 0.35, 1.0)
const DURABILITY_MID_COLOR := Color(0.92, 0.76, 0.25, 1.0)
const DURABILITY_LOW_COLOR := Color(0.85, 0.23, 0.2, 1.0)

var slot_index := -1
var current_item_id := ""
var current_quantity := 0
var current_purity := 0.0
var current_durability = null
var current_max_durability = null
var is_drag_origin := false
var is_equipped := false
var _placeholder_textures := {}
var _press_start_pos := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	broken_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	broken_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	durability_bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	durability_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_start_pos = event.global_position
			drag_started.emit(slot_index)
		else:
			if event.global_position.distance_to(_press_start_pos) < 10.0:
				clicked.emit(slot_index)
			drag_released.emit(slot_index)
		accept_event()

func update_slot(item_id: String, quantity: int, purity: float, durability = null, max_durability = null) -> void:
	current_item_id = item_id
	current_quantity = quantity
	current_purity = purity
	current_durability = durability
	current_max_durability = max_durability
	is_drag_origin = false

	if quantity > 0:
		item_icon.texture = _get_placeholder_texture(item_id)
		item_icon.modulate = _get_icon_color()
		quantity_label.text = str(quantity)
	else:
		current_item_id = ""

	_apply_visual_state()

func clear() -> void:
	current_item_id = ""
	current_quantity = 0
	current_purity = 0.0
	current_durability = null
	current_max_durability = null
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

	if is_equipped:
		self_modulate = Color(1.5, 1.5, 1.0) # Bright highlight
	else:
		self_modulate = Color.WHITE

	if has_stack:
		item_icon.texture = _get_placeholder_texture(current_item_id)
		item_icon.modulate = _get_icon_color()
		quantity_label.text = str(current_quantity)
	else:
		item_icon.texture = null
		quantity_label.text = ""

	var has_durability := _has_durability()
	var durability_ratio := _get_durability_ratio()
	durability_bar_background.visible = has_stack and has_durability and not is_drag_origin
	broken_overlay.visible = has_stack and has_durability and durability_ratio <= 0.0 and not is_drag_origin
	if durability_bar_background.visible:
		durability_bar_fill.color = _get_durability_color(durability_ratio)
		durability_bar_fill.size.x = durability_bar_background.size.x * durability_ratio
		durability_bar_fill.size.y = durability_bar_background.size.y

func _on_resized() -> void:
	if durability_bar_background.visible:
		durability_bar_fill.size.x = durability_bar_background.size.x * _get_durability_ratio()
		durability_bar_fill.size.y = durability_bar_background.size.y

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

func _get_icon_color() -> Color:
	var base_color := _get_item_color(current_item_id)
	if _has_durability() and _get_durability_ratio() <= 0.0:
		return _get_desaturated_color(base_color)
	return base_color

func _get_desaturated_color(base_color: Color) -> Color:
	var luminance := (base_color.r * 0.299) + (base_color.g * 0.587) + (base_color.b * 0.114)
	var grayscale := clampf(luminance, 0.18, 0.82)
	return Color(grayscale, grayscale, grayscale, base_color.a)

func _has_durability() -> bool:
	return current_durability != null and current_max_durability != null

func _get_durability_ratio() -> float:
	if not _has_durability():
		return 0.0

	var max_durability := maxf(float(current_max_durability), 0.0)
	if is_zero_approx(max_durability):
		return 0.0

	return clampf(float(current_durability) / max_durability, 0.0, 1.0)

func _get_durability_color(ratio: float) -> Color:
	if ratio >= 0.5:
		return DURABILITY_MID_COLOR.lerp(DURABILITY_HIGH_COLOR, (ratio - 0.5) / 0.5)
	return DURABILITY_LOW_COLOR.lerp(DURABILITY_MID_COLOR, ratio / 0.5)

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
