extends CanvasLayer

@onready var panel = $InventoryPanel
@onready var grid = $InventoryPanel/Grid
@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_name_label: Label = $TooltipPanel/MarginContainer/TooltipContent/NameLabel
@onready var tooltip_weight_label: Label = $TooltipPanel/MarginContainer/TooltipContent/WeightLabel
@onready var tooltip_category_label: Label = $TooltipPanel/MarginContainer/TooltipContent/CategoryLabel
@onready var onboarding_hint: PanelContainer = $OnboardingHint
@onready var inventory_hint_label: Label = $OnboardingHint/MarginContainer/HintContent/InventoryHintLabel
@onready var select_hint_label: Label = $OnboardingHint/MarginContainer/HintContent/SelectHintLabel

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")
const SLOT_COUNT := 20
const TOOLTIP_DELAY := 0.3
const TOOLTIP_OFFSET := Vector2(18, 18)
const ONBOARDING_CONFIG_PATH := "user://onboarding_hints.cfg"
const ONBOARDING_SECTION := "inventory_hints"
const INVENTORY_HINT_KEY := "inventory_seen"
const SELECT_HINT_KEY := "select_seen"

var drag_origin_index := -1
var drag_ghost: TextureRect = null
var hover_slot_index := -1
var tooltip_slot_index := -1
var tooltip_delay_timer: SceneTreeTimer = null
var inventory_hint_seen := false
var select_hint_seen := false

func _ready():
	_load_onboarding_state()
	for i in range(SLOT_COUNT):
		var slot = SLOT_SCENE.instantiate()
		grid.add_child(slot)
		slot.slot_index = i
		slot.drag_started.connect(_on_slot_drag_started)
		slot.drag_released.connect(_on_slot_drag_released)
		slot.clicked.connect(_on_slot_clicked)
		slot.hover_started.connect(_on_slot_hover_started)
		slot.hover_ended.connect(_on_slot_hover_ended)
		
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
		
	InventoryManager.inventory_changed.connect(refresh_grid)
	InventoryManager.held_item_changed.connect(func(_id): refresh_grid())
	refresh_grid()
	
	call_deferred("_setup_panel")

func _setup_panel():
	var vp_size = get_viewport().get_visible_rect().size
	panel.position = Vector2(vp_size.x, (vp_size.y - panel.size.y) / 2)
	panel.visible = false
	tooltip_panel.visible = false
	_update_onboarding_hint()

func _input(event):
	if event.is_action_pressed("toggle_inventory"):
		_mark_inventory_hint_seen()
		toggle_inventory()
	
	# Hotkeys 1-9 for slots 0-8
	for i in range(1, 10):
		if event.is_action_pressed("slot_%d" % i):
			_mark_select_hint_seen()
			InventoryManager.select_slot(i - 1)
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _is_dragging():
			_finish_drag(_get_slot_index_at_position(get_viewport().get_mouse_position()))

func _process(_delta: float) -> void:
	if drag_ghost != null:
		drag_ghost.global_position = get_viewport().get_mouse_position() - (drag_ghost.size / 2.0)
	if tooltip_panel.visible:
		_update_tooltip_position()

func toggle_inventory():
	var vp_size = get_viewport().get_visible_rect().size
	var target_x = vp_size.x
	
	if not panel.visible or panel.position.x >= vp_size.x - 1:
		# opening
		panel.visible = true
		target_x = vp_size.x - panel.size.x - 50
		refresh_grid()
	else:
		_hide_tooltip()
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", target_x, 0.4)
	
	if target_x >= vp_size.x - 1:
		# closing
		tween.tween_callback(func(): panel.visible = false)

func refresh_grid():
	var held_id = InventoryManager.get_held_item_id()
	for i in range(grid.get_child_count()):
		var slot = grid.get_child(i)
		var data = InventoryManager.get_slot_item(i)
		
		slot.is_equipped = (not data.is_empty() and data.id == held_id)
		
		if not data.is_empty():
			slot.update_slot(data.id, data.quantity, data.purity)
		else:
			slot.clear()
	
	if tooltip_panel.visible and hover_slot_index >= 0:
		_show_tooltip_for_slot(hover_slot_index)
	elif hover_slot_index == -1:
		_hide_tooltip()

func _on_slot_drag_started(slot_index: int) -> void:
	if _is_dragging():
		return
	if slot_index < 0 or slot_index >= grid.get_child_count():
		return
	
	var slot = grid.get_child(slot_index)
	if not slot.has_item():
		return
	
	_hide_tooltip()
	drag_origin_index = slot_index
	slot.set_drag_origin(true)
	_create_drag_ghost(slot)

func _on_slot_drag_released(slot_index: int) -> void:
	if _is_dragging():
		_finish_drag(slot_index)

func _on_slot_clicked(slot_index: int) -> void:
	InventoryManager.select_slot(slot_index)

func _create_drag_ghost(source_slot) -> void:
	_clear_drag_ghost()
	
	drag_ghost = TextureRect.new()
	drag_ghost.texture = source_slot.item_icon.texture
	drag_ghost.modulate = source_slot.item_icon.modulate
	drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.z_index = 4096
	drag_ghost.size = source_slot.get_global_rect().size
	drag_ghost.global_position = get_viewport().get_mouse_position() - (drag_ghost.size / 2.0)
	add_child(drag_ghost)

func _finish_drag(drop_slot_index: int) -> void:
	var from_slot := drag_origin_index
	_clear_drag_ghost()
	drag_origin_index = -1
	
	if from_slot >= 0 and from_slot < grid.get_child_count():
		grid.get_child(from_slot).set_drag_origin(false)
	
	if drop_slot_index >= 0 and drop_slot_index < grid.get_child_count() and drop_slot_index != from_slot:
		InventoryManager.swap_slots(from_slot, drop_slot_index)

func _get_slot_index_at_position(global_mouse_position: Vector2) -> int:
	for i in range(grid.get_child_count()):
		var slot = grid.get_child(i)
		if slot.get_global_rect().has_point(global_mouse_position):
			return i
	
	return -1

func _clear_drag_ghost() -> void:
	if drag_ghost != null:
		drag_ghost.queue_free()
		drag_ghost = null

func _is_dragging() -> bool:
	return drag_origin_index != -1 and drag_ghost != null

func _on_slot_hover_started(slot_index: int) -> void:
	if _is_dragging():
		return
	if slot_index < 0 or slot_index >= grid.get_child_count():
		return
	
	var slot = grid.get_child(slot_index)
	if not slot.has_item():
		_hide_tooltip()
		return
	
	hover_slot_index = slot_index
	tooltip_slot_index = -1
	tooltip_panel.visible = false
	_start_tooltip_delay(slot_index)

func _on_slot_hover_ended(slot_index: int) -> void:
	if hover_slot_index == slot_index:
		hover_slot_index = -1
	_hide_tooltip()

func _start_tooltip_delay(slot_index: int) -> void:
	var timer := get_tree().create_timer(TOOLTIP_DELAY)
	tooltip_delay_timer = timer
	timer.timeout.connect(func() -> void:
		if tooltip_delay_timer != timer:
			return
		tooltip_delay_timer = null
		if hover_slot_index != slot_index or _is_dragging() or not panel.visible:
			return
		_show_tooltip_for_slot(slot_index)
	)

func _show_tooltip_for_slot(slot_index: int) -> void:
	var data = InventoryManager.get_slot_item(slot_index)
	if data.is_empty():
		_hide_tooltip()
		return
	
	var item_id := StringName(str(data.get("id", "")))
	var element_data := ElementDatabase.get_element(item_id)
	if element_data.is_empty():
		_hide_tooltip()
		return
	
	tooltip_name_label.text = str(element_data.get("display_name", item_id))
	tooltip_weight_label.text = "Weight: %.1f" % float(element_data.get("weight", 0.0))
	tooltip_category_label.text = "Category: %s" % _format_category(str(element_data.get("category", "")))
	tooltip_slot_index = slot_index
	tooltip_panel.visible = true
	_update_tooltip_position()

func _hide_tooltip() -> void:
	tooltip_delay_timer = null
	tooltip_slot_index = -1
	tooltip_panel.visible = false

func _update_tooltip_position() -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	var tooltip_size := tooltip_panel.size
	var target_position := get_viewport().get_mouse_position() + TOOLTIP_OFFSET
	
	if target_position.x + tooltip_size.x > viewport_rect.size.x:
		target_position.x = viewport_rect.size.x - tooltip_size.x - 8.0
	if target_position.y + tooltip_size.y > viewport_rect.size.y:
		target_position.y = viewport_rect.size.y - tooltip_size.y - 8.0
	
	tooltip_panel.global_position = Vector2(
		maxf(8.0, target_position.x),
		maxf(8.0, target_position.y)
	)

func _format_category(category: String) -> String:
	if category.is_empty():
		return "Unknown"
	
	var words := category.split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)

func _load_onboarding_state() -> void:
	var config := ConfigFile.new()
	var err := config.load(ONBOARDING_CONFIG_PATH)
	if err != OK:
		return
	inventory_hint_seen = bool(config.get_value(ONBOARDING_SECTION, INVENTORY_HINT_KEY, false))
	select_hint_seen = bool(config.get_value(ONBOARDING_SECTION, SELECT_HINT_KEY, false))

func _save_onboarding_state() -> void:
	var config := ConfigFile.new()
	config.set_value(ONBOARDING_SECTION, INVENTORY_HINT_KEY, inventory_hint_seen)
	config.set_value(ONBOARDING_SECTION, SELECT_HINT_KEY, select_hint_seen)
	config.save(ONBOARDING_CONFIG_PATH)

func _mark_inventory_hint_seen() -> void:
	if inventory_hint_seen:
		return
	inventory_hint_seen = true
	_save_onboarding_state()
	_update_onboarding_hint()

func _mark_select_hint_seen() -> void:
	if select_hint_seen:
		return
	select_hint_seen = true
	_save_onboarding_state()
	_update_onboarding_hint()

func _update_onboarding_hint() -> void:
	if onboarding_hint == null:
		return
	inventory_hint_label.visible = not inventory_hint_seen
	select_hint_label.visible = not select_hint_seen
	onboarding_hint.visible = not inventory_hint_seen or not select_hint_seen
