extends CanvasLayer

@onready var panel = $InventoryPanel
@onready var grid = $InventoryPanel/Grid

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")

func _ready():
	for i in range(20):
		var slot = SLOT_SCENE.instantiate()
		grid.add_child(slot)
		
		# Set minimum size for GridContainer to respect
		slot.custom_minimum_size = Vector2(64, 64)
		
		# Set ItemIcon anchors and modes
		var icon = slot.get_node("ItemIcon")
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Set QuantityLabel anchors
		var label = slot.get_node("QuantityLabel")
		label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		
	call_deferred("_setup_panel")

func _setup_panel():
	var vp_size = get_viewport().get_visible_rect().size
	panel.position = Vector2(vp_size.x, (vp_size.y - panel.size.y) / 2)
	panel.visible = false

func _input(event):
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed and not event.echo:
		toggle_inventory()

func toggle_inventory():
	var vp_size = get_viewport().get_visible_rect().size
	var target_x = vp_size.x
	
	if not panel.visible or panel.position.x >= vp_size.x - 1:
		# opening
		panel.visible = true
		target_x = vp_size.x - panel.size.x - 50
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", target_x, 0.4)
	
	if target_x >= vp_size.x - 1:
		# closing
		tween.tween_callback(func(): panel.visible = false)
