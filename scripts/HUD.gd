extends CanvasLayer

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
@onready var held_item_icon: TextureRect = $HeldItemContainer/HBoxContainer/ActiveItemIcon
@onready var held_item_label: Label = $HeldItemContainer/HBoxContainer/ActiveItemLabel
@onready var carry_vignette: ColorRect = $CarryVignette

const CARRY_VIGNETTE_MAX_ALPHA := 0.35
const CARRY_VIGNETTE_START_RATIO := 0.9
const CARRY_VIGNETTE_END_RATIO := 1.0

var _placeholder_textures := {}

func _ready() -> void:
	GameManager.player_health_changed.connect(_update_health)
	InventoryManager.inventory_changed.connect(_refresh_held_item)
	InventoryManager.held_item_changed.connect(_on_held_item_changed)
	InventoryManager.weight_changed.connect(_on_weight_changed)
	
	_update_health(GameManager.player_health, GameManager.max_player_health)
	_refresh_held_item()
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)

func _update_health(current_health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_label.text = "%d / %d HP" % [current_health, max_health]

func _refresh_held_item() -> void:
	var held_item := InventoryManager.get_held_item()
	if held_item.is_empty():
		held_item_icon.texture = null
		held_item_icon.modulate = Color(1.0, 1.0, 1.0, 0.25)
		held_item_label.text = "Hands Empty"
		return
	
	var item_id := str(held_item.get("id", ""))
	var element_data := ElementDatabase.get_element(StringName(item_id))
	held_item_icon.texture = _get_placeholder_texture(item_id)
	held_item_icon.modulate = _get_item_color(item_id)
	held_item_label.text = str(element_data.get("display_name", item_id))

func _on_held_item_changed(_item_id: String) -> void:
	_refresh_held_item()

func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	var capacity_ratio := 0.0
	if carry_capacity > 0.0:
		capacity_ratio = total_weight / carry_capacity

	var overlay_alpha := 0.0
	if capacity_ratio >= CARRY_VIGNETTE_START_RATIO:
		var alpha_ratio := inverse_lerp(CARRY_VIGNETTE_START_RATIO, CARRY_VIGNETTE_END_RATIO, minf(capacity_ratio, CARRY_VIGNETTE_END_RATIO))
		overlay_alpha = alpha_ratio * CARRY_VIGNETTE_MAX_ALPHA

	carry_vignette.color.a = overlay_alpha

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
	texture.width = 48
	texture.height = 48
	_placeholder_textures[item_id] = texture
	return texture
