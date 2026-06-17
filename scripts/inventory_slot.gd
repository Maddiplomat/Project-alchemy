extends Panel
class_name InventorySlot

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
const SLOT_BG_DEFAULT := Color(0.18, 0.19, 0.22, 0.96)
const SLOT_BORDER_DEFAULT := Color(0.32, 0.34, 0.38, 1.0)
const SLOT_BG_CHARCOAL := Color(0.08, 0.08, 0.09, 0.98)
const SLOT_BORDER_CHARCOAL := Color(0.20, 0.20, 0.22, 1.0)
const SLOT_BORDER_SULFUR := Color(0.96, 0.86, 0.25, 1.0)
const SLOT_BG_SULFUR := Color(0.21, 0.19, 0.08, 0.98)
const SLOT_BORDER_LITHIUM := Color(0.42, 0.78, 1.0, 1.0)
const SLOT_BG_LITHIUM := Color(0.09, 0.14, 0.20, 0.98)
const SLOT_BORDER_LITHIUM_RISK := Color(0.62, 0.92, 1.0, 1.0)
const SLOT_BG_LITHIUM_RISK := Color(0.08, 0.18, 0.24, 0.98)
const SLOT_BORDER_RISK := Color(0.96, 0.18, 0.18, 1.0)
const SLOT_BG_RISK := Color(0.31, 0.08, 0.08, 0.98)
const QUANTITY_FONT_COLOR := Color(0.97, 0.97, 0.97, 1.0)
const QUANTITY_OUTLINE_COLOR := Color(0.03, 0.04, 0.05, 0.95)

var slot_index := -1
var item_id: StringName = &""
var quantity: int = 0
var purity: float = 0.0
var is_active: bool = false
var item_color: Color = Color.WHITE
var current_durability = null
var current_max_durability = null
var is_drag_origin := false
var is_equipped := false
var _placeholder_textures := {}
var _press_start_pos := Vector2.ZERO
var _pulse_time := 0.0
var _carrier_risk_active := false
var _carrier_risk_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	broken_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	broken_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	durability_bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	durability_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	quantity_label.offset_left = 6.0
	quantity_label.offset_top = -22.0
	quantity_label.offset_right = -6.0
	quantity_label.offset_bottom = -4.0
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.add_theme_color_override("font_color", QUANTITY_FONT_COLOR)
	quantity_label.add_theme_color_override("font_outline_color", QUANTITY_OUTLINE_COLOR)
	quantity_label.add_theme_constant_override("outline_size", 4)
	quantity_label.add_theme_font_size_override("font_size", 13)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	set_process(true)
	_apply_background_style()


func _process(delta: float) -> void:
	if _carrier_risk_active and has_item() and _supports_carrier_risk_visuals():
		_carrier_risk_time += delta
		_apply_background_style()
	elif has_item() and _supports_passive_risk_pulse() and is_equipped:
		_pulse_time += delta
		_apply_background_style()
	elif _pulse_time != 0.0 or _carrier_risk_time != 0.0:
		_pulse_time = 0.0
		_carrier_risk_time = 0.0
		_apply_background_style()

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

func update_display() -> void:
	is_equipped = is_active
	is_drag_origin = false
	_apply_visual_state()


func update_slot(next_item_id: String, next_quantity: int, next_purity: float, durability = null, max_durability = null) -> void:
	item_id = StringName(next_item_id)
	quantity = next_quantity
	purity = next_purity
	current_durability = durability
	current_max_durability = max_durability
	update_display()

func clear() -> void:
	item_id = &""
	quantity = 0
	purity = 0.0
	is_active = false
	item_color = Color.WHITE
	current_durability = null
	current_max_durability = null
	is_drag_origin = false
	is_equipped = false
	_apply_visual_state()

func has_item() -> bool:
	return not item_id.is_empty() and quantity > 0

func set_drag_origin(active: bool) -> void:
	is_drag_origin = active
	_apply_visual_state()


func set_carrier_risk_alert(active: bool) -> void:
	if _carrier_risk_active == active:
		return
	_carrier_risk_active = active
	if not active:
		_carrier_risk_time = 0.0
	_apply_background_style()

func _apply_visual_state() -> void:
	var has_stack := has_item()
	item_icon.visible = has_stack and not is_drag_origin
	quantity_label.visible = has_stack and not is_drag_origin

	if is_equipped:
		self_modulate = Color(1.5, 1.5, 1.0) # Bright highlight
	else:
		self_modulate = Color.WHITE

	if has_stack:
		item_icon.texture = _get_placeholder_texture(String(item_id))
		item_icon.modulate = _get_icon_color()
		quantity_label.text = "x%d" % quantity
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

	_apply_background_style()

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
		"charcoal":
			return Color(0.17, 0.18, 0.20, 1.0)
		"distillation_kit":
			return Color(0.78, 0.67, 0.46, 1.0)
		"sulfur":
			return Color(0.95, 0.87, 0.24, 1.0)
		"lithium":
			return Color(0.84, 0.90, 0.97, 1.0)
		"sulfuric_bolt":
			return Color(0.76, 0.90, 0.22, 1.0)
		_:
			return Color.WHITE


func _apply_background_style() -> void:
	var current_item_id := String(item_id)
	var is_charcoal_slot := has_item() and current_item_id == "charcoal"
	var is_sulfur_held_slot := has_item() and current_item_id == "sulfur" and is_equipped
	var is_sulfur_risk_slot := has_item() and current_item_id == "sulfur" and _carrier_risk_active
	var is_lithium_held_slot := has_item() and current_item_id == "lithium" and is_equipped
	var is_lithium_risk_slot := has_item() and current_item_id == "lithium" and _carrier_risk_active
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = (
		SLOT_BG_RISK if is_sulfur_risk_slot else
		(SLOT_BG_LITHIUM_RISK if is_lithium_risk_slot else
		(SLOT_BG_SULFUR if is_sulfur_held_slot else
		(SLOT_BG_LITHIUM if is_lithium_held_slot else
		(SLOT_BG_CHARCOAL if is_charcoal_slot else SLOT_BG_DEFAULT))))
	)
	if is_sulfur_risk_slot:
		var flash_phase := fmod(_carrier_risk_time * 4.0, 1.0)
		var flash_alpha := 1.0 if flash_phase < 0.5 else 0.22
		panel_style.border_color = Color(SLOT_BORDER_RISK.r, SLOT_BORDER_RISK.g, SLOT_BORDER_RISK.b, flash_alpha)
	elif is_lithium_risk_slot:
		var risk_pulse_alpha := 0.55 + 0.35 * sin(_carrier_risk_time * TAU * 1.4)
		panel_style.border_color = Color(
			SLOT_BORDER_LITHIUM_RISK.r,
			SLOT_BORDER_LITHIUM_RISK.g,
			SLOT_BORDER_LITHIUM_RISK.b,
			risk_pulse_alpha
		)
	elif is_sulfur_held_slot:
		var pulse_alpha := 0.55 + 0.25 * sin(_pulse_time * TAU * 1.2)
		panel_style.border_color = Color(
			SLOT_BORDER_SULFUR.r,
			SLOT_BORDER_SULFUR.g,
			SLOT_BORDER_SULFUR.b,
			pulse_alpha
		)
	elif is_lithium_held_slot:
		var lithium_pulse_alpha := 0.45 + 0.28 * sin(_pulse_time * TAU * 0.9)
		panel_style.border_color = Color(
			SLOT_BORDER_LITHIUM.r,
			SLOT_BORDER_LITHIUM.g,
			SLOT_BORDER_LITHIUM.b,
			lithium_pulse_alpha
		)
	else:
		panel_style.border_color = SLOT_BORDER_CHARCOAL if is_charcoal_slot else SLOT_BORDER_DEFAULT
	var emphasized_border := is_sulfur_held_slot or is_sulfur_risk_slot or is_lithium_held_slot or is_lithium_risk_slot
	panel_style.border_width_left = 2 if emphasized_border else 1
	panel_style.border_width_top = 2 if emphasized_border else 1
	panel_style.border_width_right = 2 if emphasized_border else 1
	panel_style.border_width_bottom = 2 if emphasized_border else 1
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.corner_radius_bottom_left = 6
	add_theme_stylebox_override("panel", panel_style)


func _supports_passive_risk_pulse() -> bool:
	return item_id == &"sulfur" or item_id == &"lithium"


func _supports_carrier_risk_visuals() -> bool:
	return _supports_passive_risk_pulse()

func _get_icon_color() -> Color:
	var base_color := item_color if item_color != Color.WHITE else _get_item_color(String(item_id))
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
