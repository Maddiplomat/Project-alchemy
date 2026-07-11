extends CanvasLayer

@onready var panel = $InventoryPanel
@onready var grid = $InventoryPanel/PanelContent/InventoryColumn/Grid
@onready var weight_bar: ProgressBar = $InventoryPanel/PanelContent/InventoryColumn/WeightRow/WeightBar
@onready var weight_label: Label = $InventoryPanel/PanelContent/InventoryColumn/WeightRow/WeightLabel
@onready var inventory_keybind_label: Label = $InventoryPanel/KeybindStrip/InventoryKeybindLabel
@onready var select_keybind_label: Label = $InventoryPanel/KeybindStrip/SelectKeybindLabel
@onready var crafting_panel: Control = $InventoryPanel/PanelContent/CraftingPanel
@onready var crafting_hint_label: Label = $InventoryPanel/PanelContent/CraftingPanel/MarginContainer/CraftingContent/CraftingHint
@onready var recipes_list: VBoxContainer = $InventoryPanel/PanelContent/CraftingPanel/MarginContainer/CraftingContent/RecipesScroll/RecipesList
@onready var phone_hotbar: PanelContainer = $PhoneHotbar
@onready var hotbar_slots: HBoxContainer = $PhoneHotbar/MarginContainer/HotbarRow/HotbarSlots
@onready var mobile_action_panel: PanelContainer = $MobileActionPanel
@onready var selected_item_label: Label = $MobileActionPanel/MarginContainer/VBoxContainer/SelectedItemLabel
@onready var use_button: Button = $MobileActionPanel/MarginContainer/VBoxContainer/ActionButtons/UseButton
@onready var transfer_button: Button = $MobileActionPanel/MarginContainer/VBoxContainer/ActionButtons/TransferButton
@onready var split_button: Button = $MobileActionPanel/MarginContainer/VBoxContainer/ActionButtons/SplitButton
@onready var drop_button: Button = $MobileActionPanel/MarginContainer/VBoxContainer/ActionButtons/DropButton
@onready var details_button: Button = $MobileActionPanel/MarginContainer/VBoxContainer/DetailsButton
@onready var action_hint_label: Label = $MobileActionPanel/MarginContainer/VBoxContainer/ActionHintLabel
@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_name_label: Label = $TooltipPanel/MarginContainer/TooltipContent/NameLabel
@onready var tooltip_weight_label: Label = $TooltipPanel/MarginContainer/TooltipContent/WeightLabel
@onready var tooltip_category_label: Label = $TooltipPanel/MarginContainer/TooltipContent/CategoryLabel
@onready var tooltip_durability_label: Label = $TooltipPanel/MarginContainer/TooltipContent/DurabilityLabel
@onready var quantity_modal: PanelContainer = $QuantityModal
@onready var quantity_title_label: Label = $QuantityModal/MarginContainer/VBoxContainer/TitleLabel
@onready var quantity_summary_label: Label = $QuantityModal/MarginContainer/VBoxContainer/SummaryLabel
@onready var quantity_value_label: Label = $QuantityModal/MarginContainer/VBoxContainer/StepperRow/QuantityValueLabel
@onready var quantity_minus_button: Button = $QuantityModal/MarginContainer/VBoxContainer/StepperRow/MinusButton
@onready var quantity_plus_button: Button = $QuantityModal/MarginContainer/VBoxContainer/StepperRow/PlusButton
@onready var quantity_cancel_button: Button = $QuantityModal/MarginContainer/VBoxContainer/ModalButtons/CancelButton
@onready var quantity_confirm_button: Button = $QuantityModal/MarginContainer/VBoxContainer/ModalButtons/ConfirmButton
@onready var crafting_highlight: Panel = $InventoryPanel/PanelContent/CraftingPanel/CraftingHighlight
@onready var crafting_pulse_player: AnimationPlayer = $InventoryPanel/PanelContent/CraftingPanel/CraftingPulsePlayer

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")
const SLOT_COUNT := InventoryManager.MAX_SLOTS
const TOOLTIP_DELAY := 0.3
const TOOLTIP_OFFSET := Vector2(18, 18)
const SLOT_TOUCH_SIZE := Vector2(80, 80)
const CRAFTING_PULSE_ANIMATION_NAME := "crafting_pulse"
const WEIGHT_NORMAL_COLOR := Color(0.45, 0.83, 0.61, 1.0)
const WEIGHT_WARNING_COLOR := Color(0.95, 0.67, 0.29, 1.0)
const WEIGHT_DANGER_COLOR := Color(0.89, 0.29, 0.24, 1.0)
const CRAFT_READY_COLOR := Color(0.45, 0.83, 0.61, 1.0)
const CRAFT_LOCKED_COLOR := Color(0.36, 0.39, 0.43, 1.0)
const RECIPE_ROW_BG_COLOR := Color(0.14, 0.16, 0.19, 0.9)
const RECIPE_ROW_BORDER_COLOR := Color(0.29, 0.31, 0.36, 1.0)
const RECIPE_DURABILITY_COLOR := Color(0.75, 0.86, 0.43, 1.0)
const ITEM_ICON_SIZE := Vector2(34, 34)
const SELECT_KEYBIND_BASE_TEXT := "Tap slots to equip. Long-press for details."
const DESKTOP_KEYBIND_BASE_TEXT := "1-5: select active item   F6/Cmd+S: save game"
const DRAG_QUANTITY_HINT_TEXT := "Use Split or Drop to choose a quantity."
const WORLD_DROP_DISTANCE := 22.0
const DISTILLATION_KIT_ITEM_ID := &"distillation_kit"
const SULFUR_ITEM_ID := &"sulfur"
const SULFURIC_BOLT_ITEM_ID := &"sulfuric_bolt"
const RUST_BOLT_ITEM_ID := &"rust_bolt"
const TOUCH_UI_MARGIN := 14.0

enum QuantityAction {
	NONE,
	DROP,
	SPLIT_DROP,
}

var drag_origin_index := -1
var drag_ghost: TextureRect = null
var drag_source_quantity := 0
var drag_quantity := 0
var selected_slot_index := 0
var hover_slot_index := -1
var tooltip_slot_index := -1
var tooltip_delay_timer: SceneTreeTimer = null
var recipe_row_refs: Dictionary[StringName, Dictionary] = {}
var _placeholder_textures := {}
var _carrier_risk_item_id: StringName = &""
var _tooltip_hint_label: Label = null
var _hotbar_slots: Array[InventorySlot] = []
var _pending_transfer_slot_index := -1
var _quantity_modal_action := QuantityAction.NONE
var _quantity_modal_slot_index := -1
var _quantity_modal_value := 1
var _drag_pointer_position := Vector2.ZERO

func _ready():
	_build_slot_row(grid)
	_build_hotbar()
	InventoryManager.inventory_changed.connect(refresh_grid.unbind(1))
	InventoryManager.active_slot_changed.connect(func(_id): refresh_grid())
	InventoryManager.weight_changed.connect(_on_weight_changed)
	if MobileInputRouter != null and MobileInputRouter.has_signal("input_mode_changed"):
		MobileInputRouter.input_mode_changed.connect(func(_mode: StringName) -> void:
			_refresh_touch_layout()
			_update_drag_hint_label()
		)
	if EventBus != null and EventBus.has_signal("discovery_entry_added"):
		EventBus.discovery_entry_added.connect(func(_entry: Dictionary) -> void:
			_build_recipe_rows()
			_refresh_recipe_states()
		)
	if has_node("/root/CarrierRiskSystem"):
		CarrierRiskSystem.carrier_risk_warning.connect(_on_carrier_risk_warning)
		CarrierRiskSystem.carrier_risk_cleared.connect(_on_carrier_risk_cleared)
		CarrierRiskSystem.carrier_risk_ignition.connect(_on_carrier_risk_ignition)
	if crafting_panel != null:
		crafting_panel.visible = false
	use_button.pressed.connect(_on_use_button_pressed)
	transfer_button.pressed.connect(_on_transfer_button_pressed)
	split_button.pressed.connect(_on_split_button_pressed)
	drop_button.pressed.connect(_on_drop_button_pressed)
	details_button.pressed.connect(_on_details_button_pressed)
	quantity_minus_button.pressed.connect(func() -> void: _adjust_quantity_modal(-1))
	quantity_plus_button.pressed.connect(func() -> void: _adjust_quantity_modal(1))
	quantity_cancel_button.pressed.connect(_close_quantity_modal)
	quantity_confirm_button.pressed.connect(_confirm_quantity_modal)
	_ensure_tooltip_hint_label()
	_build_recipe_rows()
	_refresh_recipe_states()
	_refresh_crafting_hint()
	selected_slot_index = InventoryManager.active_slot_index
	refresh_grid()
	_update_weight_display(InventoryManager.total_weight, InventoryManager.carry_capacity)
	_refresh_touch_layout()
	_update_drag_hint_label()
	get_viewport().size_changed.connect(func() -> void:
		_position_inventory_panel()
		_position_touch_panels()
	)

	call_deferred("_setup_panel")

func _setup_panel():
	_position_inventory_panel()
	panel.visible = false
	tooltip_panel.visible = false
	_position_touch_panels()

func _input(event):
	if event.is_action_pressed("toggle_inventory"):
		if _is_inventory_toggle_blocked():
			return
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if not _prefers_touch_ui():
		for i in range(1, mini(SLOT_COUNT, 9) + 1):
			if event.is_action_pressed("slot_%d" % i):
				_select_slot(i - 1, true)
				return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _is_dragging():
		var release_position := get_viewport().get_mouse_position()
		_finish_drag(_get_slot_index_at_position(release_position), release_position)

func _process(_delta: float) -> void:
	if drag_ghost != null:
		var pointer_position := _get_pointer_screen_position()
		drag_ghost.global_position = pointer_position - (drag_ghost.size / 2.0)
	if tooltip_panel.visible:
		_update_tooltip_position()
	_refresh_touch_layout()

func toggle_inventory():
	var vp_size = get_viewport().get_visible_rect().size
	var target_x = vp_size.x

	if not panel.visible or panel.position.x >= vp_size.x - 1:
		panel.visible = true
		_position_inventory_panel()
		target_x = panel.position.x
		refresh_grid()
	else:
		_hide_tooltip()
		_hide_mobile_action_panel()
		_close_quantity_modal()
		target_x = vp_size.x + 16.0

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", target_x, 0.4)

	if target_x >= vp_size.x - 1:
		tween.tween_callback(func(): panel.visible = false)


func _is_inventory_toggle_blocked() -> bool:
	var build_system := get_node_or_null("/root/BuildSystem")
	if build_system != null and build_system.has_method("is_build_mode_active"):
		if bool(build_system.call("is_build_mode_active")):
			return true
	for station_ui in get_tree().get_nodes_in_group(&"station_inventory_drop_target"):
		if station_ui != null and station_ui.has_method("is_open") and bool(station_ui.is_open()):
			return false
	var player := GameManager.get_player()
	return player != null and player.has_method("is_input_paused") and bool(player.call("is_input_paused"))

func refresh_grid():
	selected_slot_index = clampi(selected_slot_index, 0, SLOT_COUNT - 1)
	var active_index = InventoryManager.active_slot_index
	for i in range(grid.get_child_count()):
		var slot = grid.get_child(i)
		var data = InventoryManager.get_slot_data(i)
		slot.is_equipped = (i == active_index and data.item_id != &"")
		if data.item_id != &"":
			slot.update_slot(String(data.item_id), data.quantity, data.purity, null, null)
		else:
			slot.clear()
		slot.set_carrier_risk_alert(not _carrier_risk_item_id.is_empty() and data.item_id == _carrier_risk_item_id)
	_refresh_hotbar()
	_refresh_mobile_action_panel()
	if tooltip_panel.visible and (hover_slot_index >= 0 or selected_slot_index >= 0):
		_show_tooltip_for_slot(hover_slot_index if hover_slot_index >= 0 else selected_slot_index)
	elif hover_slot_index == -1 and not _prefers_touch_ui():
		_hide_tooltip()
	_refresh_recipe_states()
	_refresh_crafting_hint()


func _on_carrier_risk_warning(element_id: StringName, _seconds_remaining: int) -> void:
	_carrier_risk_item_id = element_id
	_apply_carrier_risk_slot_state()


func _on_carrier_risk_cleared(element_id: StringName) -> void:
	if element_id != _carrier_risk_item_id:
		return
	_carrier_risk_item_id = &""
	_apply_carrier_risk_slot_state()


func _on_carrier_risk_ignition(element_id: StringName) -> void:
	if element_id == _carrier_risk_item_id:
		_carrier_risk_item_id = &""
	_apply_carrier_risk_slot_state()


func _apply_carrier_risk_slot_state() -> void:
	for i in range(grid.get_child_count()):
		var slot = grid.get_child(i)
		var data = InventoryManager.get_slot_data(i)
		slot.set_carrier_risk_alert(not _carrier_risk_item_id.is_empty() and data.item_id == _carrier_risk_item_id)
	for slot_index in range(_hotbar_slots.size()):
		var hotbar_slot := _hotbar_slots[slot_index]
		var hotbar_data := InventoryManager.get_slot_data(slot_index)
		hotbar_slot.set_carrier_risk_alert(not _carrier_risk_item_id.is_empty() and hotbar_data.item_id == _carrier_risk_item_id)

func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	_update_weight_display(total_weight, carry_capacity)

func _update_weight_display(total_weight: float, carry_capacity: float) -> void:
	var safe_capacity := maxf(carry_capacity, 0.0)
	var displayed_weight := minf(total_weight, safe_capacity) if safe_capacity > 0.0 else 0.0
	var weight_ratio := total_weight / safe_capacity if safe_capacity > 0.0 else 0.0

	weight_bar.max_value = safe_capacity
	weight_bar.value = displayed_weight
	weight_label.text = "%.1f / %.1f kg" % [total_weight, safe_capacity]

	if weight_ratio > 1.0:
		weight_bar.modulate = WEIGHT_DANGER_COLOR
	elif weight_ratio >= 0.8:
		weight_bar.modulate = WEIGHT_WARNING_COLOR
	else:
		weight_bar.modulate = WEIGHT_NORMAL_COLOR

func _build_slot_row(target_row: Container) -> void:
	for i in range(SLOT_COUNT):
		var slot := SLOT_SCENE.instantiate() as InventorySlot
		target_row.add_child(slot)
		_configure_slot(slot, i)

func _build_hotbar() -> void:
	for i in range(SLOT_COUNT):
		var slot := SLOT_SCENE.instantiate() as InventorySlot
		hotbar_slots.add_child(slot)
		_configure_slot(slot, i)
		slot.custom_minimum_size = SLOT_TOUCH_SIZE
		_hotbar_slots.append(slot)

func _configure_slot(slot: InventorySlot, slot_index: int) -> void:
	slot.slot_index = slot_index
	slot.drag_started.connect(_on_slot_drag_started)
	slot.drag_released.connect(_on_slot_drag_released)
	slot.clicked.connect(_on_slot_clicked)
	slot.hover_started.connect(_on_slot_hover_started)
	slot.hover_ended.connect(_on_slot_hover_ended)
	slot.long_pressed.connect(_on_slot_long_pressed)
	slot.custom_minimum_size = SLOT_TOUCH_SIZE
	var icon := slot.get_node("ItemIcon") as TextureRect
	if icon != null:
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var label := slot.get_node("QuantityLabel") as Label
	if label != null:
		label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func _on_slot_drag_started(slot_index: int) -> void:
	if _is_dragging():
		return
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return
	var slot := _get_slot_control(slot_index)
	if slot == null or not slot.has_item():
		return
	_hide_tooltip()
	_hide_mobile_action_panel()
	_close_quantity_modal()
	drag_origin_index = slot_index
	drag_source_quantity = int(InventoryManager.get_slot_data(slot_index).get("quantity", 0))
	drag_quantity = drag_source_quantity
	slot.set_drag_origin(true)
	_create_drag_ghost(slot)
	_update_drag_hint_label()
	_drag_pointer_position = _get_pointer_screen_position()

func _on_slot_drag_released(slot_index: int) -> void:
	if _is_dragging():
		_finish_drag(slot_index, _drag_pointer_position if _drag_pointer_position != Vector2.ZERO else _get_pointer_screen_position())

func _on_slot_clicked(slot_index: int) -> void:
	selected_slot_index = slot_index
	if _pending_transfer_slot_index >= 0 and _pending_transfer_slot_index != slot_index:
		InventoryManager.swap_slots(_pending_transfer_slot_index, slot_index)
		_pending_transfer_slot_index = -1
		refresh_grid()
		return
	_select_slot(slot_index, true)
	if _prefers_touch_ui():
		_show_mobile_action_panel(slot_index)

func _on_slot_long_pressed(slot_index: int) -> void:
	selected_slot_index = slot_index
	_show_tooltip_for_slot(slot_index)
	_show_mobile_action_panel(slot_index)

func _create_drag_ghost(source_slot: InventorySlot) -> void:
	_clear_drag_ghost()
	drag_ghost = TextureRect.new()
	drag_ghost.texture = source_slot.item_icon.texture
	drag_ghost.modulate = source_slot.item_icon.modulate
	drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.z_index = 4096
	drag_ghost.size = source_slot.get_global_rect().size
	drag_ghost.global_position = _get_pointer_screen_position() - (drag_ghost.size / 2.0)
	var quantity_badge := Label.new()
	quantity_badge.name = "QuantityBadge"
	quantity_badge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	quantity_badge.offset_left = 6.0
	quantity_badge.offset_top = -24.0
	quantity_badge.offset_right = -6.0
	quantity_badge.offset_bottom = -4.0
	quantity_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_badge.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97, 1.0))
	quantity_badge.add_theme_font_size_override("font_size", 14)
	drag_ghost.add_child(quantity_badge)

	add_child(drag_ghost)
	_update_drag_ghost_quantity()

func _finish_drag(drop_slot_index: int, release_mouse_position: Vector2) -> void:
	_drag_pointer_position = release_mouse_position
	var from_slot := drag_origin_index
	var quantity_to_drop := drag_quantity
	_clear_drag_ghost()
	drag_origin_index = -1
	drag_source_quantity = 0
	drag_quantity = 0
	_update_drag_hint_label()
	if from_slot >= 0 and from_slot < SLOT_COUNT:
		var from_control := _get_slot_control(from_slot)
		if from_control != null:
			from_control.set_drag_origin(false)
	if drop_slot_index >= 0 and drop_slot_index < SLOT_COUNT and drop_slot_index != from_slot:
		InventoryManager.swap_slots(from_slot, drop_slot_index)
		selected_slot_index = drop_slot_index
		refresh_grid()
		return
	if from_slot < 0:
		return
	var dragged_item := InventoryManager.get_slot_data(from_slot)
	if dragged_item.item_id == &"":
		return
	if _try_drop_to_station_ui(dragged_item, quantity_to_drop):
		return
	if not _prefers_touch_ui() and _should_drop_to_world(release_mouse_position):
		_try_drop_to_world(dragged_item, quantity_to_drop)

func _get_slot_index_at_position(global_mouse_position: Vector2) -> int:
	for i in range(SLOT_COUNT):
		var slot := _get_slot_control(i)
		if slot == null:
			continue
		if slot.get_global_rect().has_point(global_mouse_position):
			return i
	return -1

func _clear_drag_ghost() -> void:
	if drag_ghost != null:
		drag_ghost.queue_free()
		drag_ghost = null

func _is_dragging() -> bool:
	return drag_origin_index != -1 and drag_ghost != null


func _adjust_drag_quantity(delta: int) -> void:
	if not _is_dragging() or drag_source_quantity <= 1:
		return

	drag_quantity = clampi(drag_quantity + delta, 1, drag_source_quantity)
	_update_drag_ghost_quantity()


func _update_drag_ghost_quantity() -> void:
	if drag_ghost == null:
		return
	var quantity_badge := drag_ghost.get_node_or_null("QuantityBadge") as Label
	if quantity_badge == null:
		return
	quantity_badge.text = "x%d" % drag_quantity


func _update_drag_hint_label() -> void:
	var touch_mode := _prefers_touch_ui()
	if inventory_keybind_label != null:
		inventory_keybind_label.text = "Use the five-slot hotbar." if touch_mode else "Tab: open inventory"
	if select_keybind_label != null:
		select_keybind_label.text = (
			"%s | %s" % [SELECT_KEYBIND_BASE_TEXT, DRAG_QUANTITY_HINT_TEXT]
			if touch_mode and _is_dragging() and drag_source_quantity > 1 else
			(SELECT_KEYBIND_BASE_TEXT if touch_mode else DESKTOP_KEYBIND_BASE_TEXT)
		)


func _try_drop_to_station_ui(dragged_item: Dictionary, initial_drag_quantity: int) -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	var item_id := StringName(str(dragged_item.get("id", "")))
	var quantity := mini(initial_drag_quantity, int(dragged_item.get("quantity", 0)))
	if item_id.is_empty() or quantity <= 0:
		return false
	var pointer_position := _drag_pointer_position if _drag_pointer_position != Vector2.ZERO else _get_pointer_screen_position()
	for station_ui in get_tree().get_nodes_in_group(&"station_inventory_drop_target"):
		if station_ui == null or not is_instance_valid(station_ui):
			continue
		if current_scene != station_ui and not current_scene.is_ancestor_of(station_ui):
			continue
		if not station_ui.has_method("handle_inventory_drop"):
			continue
		if not station_ui.handle_inventory_drop(pointer_position, item_id, quantity):
			continue
		InventoryManager.remove_element(item_id, quantity)
		return true

	return false


func _should_drop_to_world(release_mouse_position: Vector2) -> bool:
	return not panel.get_global_rect().has_point(release_mouse_position)


func _try_drop_to_world(dragged_item: Dictionary, initial_drag_quantity: int) -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	var item_id := StringName(str(dragged_item.get("id", "")))
	var quantity := mini(initial_drag_quantity, int(dragged_item.get("quantity", 0)))
	if item_id.is_empty() or quantity <= 0:
		return false

	var player := GameManager.get_player()
	var spawn_system := current_scene.get_node_or_null("ElementSpawnSystem")
	if player == null or spawn_system == null or not spawn_system.has_method("spawn_inventory_pickup"):
		return false

	var pickup := spawn_system.call("spawn_inventory_pickup", dragged_item, _get_world_drop_position(player), quantity) as Node2D
	if pickup == null:
		return false

	if InventoryManager.get_stack(item_id).quantity >= quantity:
		InventoryManager.remove_element(item_id, quantity)
		return true

	pickup.queue_free()
	return false


func _get_world_drop_position(player: Node2D) -> Vector2:
	var direction := Vector2.DOWN
	if MobileInputRouter != null and MobileInputRouter.has_touch_aim():
		direction = player.global_position.direction_to(
			get_viewport().get_canvas_transform().affine_inverse() * MobileInputRouter.get_touch_aim_screen_position()
		)
	elif MobileInputRouter != null and MobileInputRouter.has_touch_pointer():
		direction = player.global_position.direction_to(
			get_viewport().get_canvas_transform().affine_inverse() * MobileInputRouter.get_touch_pointer_screen_position()
		)
	else:
		var viewport_rect := get_viewport().get_visible_rect()
		var screen_center := viewport_rect.size * 0.5
		direction = (get_viewport().get_mouse_position() - screen_center).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	return player.global_position + direction * WORLD_DROP_DISTANCE

func _on_slot_hover_started(slot_index: int) -> void:
	if _prefers_touch_ui():
		return
	if _is_dragging():
		return
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return
	var slot := _get_slot_control(slot_index)
	if not slot.has_item():
		_hide_tooltip()
		return
	hover_slot_index = slot_index
	tooltip_slot_index = -1
	tooltip_panel.visible = false
	_start_tooltip_delay(slot_index)

func _on_slot_hover_ended(slot_index: int) -> void:
	if _prefers_touch_ui():
		return
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
	var data = InventoryManager.get_slot_data(slot_index)
	if data.item_id == &"":
		_hide_tooltip()
		return

	var item_id := StringName(str(data.get("id", "")))
	var element_data := ElementDatabase.get_element(item_id)
	tooltip_name_label.text = _get_tooltip_item_name(data, element_data, item_id)
	tooltip_weight_label.text = "Weight: %.1f" % _get_tooltip_item_weight(data, element_data)
	tooltip_category_label.text = "Category: %s" % _format_category_value(data.get("category", element_data.get("category", "")))
	_update_tooltip_durability(data)
	_update_tooltip_hint(data, element_data, item_id)
	tooltip_slot_index = slot_index
	tooltip_panel.visible = true
	_update_tooltip_position()

func _hide_tooltip() -> void:
	tooltip_delay_timer = null
	tooltip_slot_index = -1
	tooltip_panel.visible = false
	tooltip_durability_label.visible = false
	if _tooltip_hint_label != null:
		_tooltip_hint_label.visible = false

func _update_tooltip_position() -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	var tooltip_size := tooltip_panel.size
	var target_position := _get_pointer_screen_position() + TOOLTIP_OFFSET
	if _prefers_touch_ui():
		var slot := _get_display_slot_control(selected_slot_index)
		if slot != null:
			target_position = slot.get_global_rect().position + Vector2(0.0, -tooltip_size.y - 12.0)
	if target_position.x + tooltip_size.x > viewport_rect.size.x:
		target_position.x = viewport_rect.size.x - tooltip_size.x - 8.0
	if target_position.y + tooltip_size.y > viewport_rect.size.y:
		target_position.y = viewport_rect.size.y - tooltip_size.y - 8.0
	tooltip_panel.global_position = Vector2(
		maxf(8.0, target_position.x),
		maxf(8.0, target_position.y)
	)

func _prefers_touch_ui() -> bool:
	return MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()

func _get_pointer_screen_position() -> Vector2:
	if MobileInputRouter != null and MobileInputRouter.has_touch_pointer():
		return MobileInputRouter.get_touch_pointer_screen_position()
	return get_viewport().get_mouse_position()

func _get_slot_control(slot_index: int) -> InventorySlot:
	if slot_index < 0 or slot_index >= grid.get_child_count():
		return null
	return grid.get_child(slot_index) as InventorySlot

func _get_display_slot_control(slot_index: int) -> InventorySlot:
	if _prefers_touch_ui() and slot_index >= 0 and slot_index < _hotbar_slots.size():
		return _hotbar_slots[slot_index]
	return _get_slot_control(slot_index)

func _select_slot(slot_index: int, set_active: bool) -> void:
	selected_slot_index = clampi(slot_index, 0, SLOT_COUNT - 1)
	if set_active:
		InventoryManager.set_active_slot(selected_slot_index)
	_refresh_mobile_action_panel()
	_refresh_hotbar()

func _refresh_hotbar() -> void:
	var active_index := InventoryManager.active_slot_index
	for slot_index in range(_hotbar_slots.size()):
		var hotbar_slot := _hotbar_slots[slot_index]
		var data := InventoryManager.get_slot_data(slot_index)
		hotbar_slot.is_equipped = slot_index == active_index and data.item_id != &""
		if data.item_id != &"":
			hotbar_slot.update_slot(String(data.item_id), data.quantity, data.purity, null, null)
		else:
			hotbar_slot.clear()
		hotbar_slot.visible = true

func _refresh_touch_layout() -> void:
	if phone_hotbar == null:
		return
	var touch_mode := _prefers_touch_ui()
	phone_hotbar.visible = touch_mode
	mobile_action_panel.visible = touch_mode and mobile_action_panel.visible
	quantity_modal.visible = touch_mode and quantity_modal.visible
	_position_touch_panels()

func _position_touch_panels() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var safe_insets := _get_safe_insets(viewport_size)
	var inset_left := float(safe_insets.get(&"left", 0.0))
	var inset_top := float(safe_insets.get(&"top", 0.0))
	var inset_right := float(safe_insets.get(&"right", 0.0))
	var inset_bottom := float(safe_insets.get(&"bottom", 0.0))
	var bottom_margin := inset_bottom + TOUCH_UI_MARGIN
	if phone_hotbar != null:
		phone_hotbar.position = Vector2(
			maxf(inset_left + TOUCH_UI_MARGIN, (viewport_size.x - phone_hotbar.size.x) * 0.5),
			viewport_size.y - phone_hotbar.size.y - bottom_margin
		)
	if mobile_action_panel != null:
		mobile_action_panel.position = Vector2(
			maxf(inset_left + TOUCH_UI_MARGIN, viewport_size.x - inset_right - mobile_action_panel.size.x - TOUCH_UI_MARGIN),
			maxf(inset_top + 88.0, viewport_size.y - mobile_action_panel.size.y - phone_hotbar.size.y - bottom_margin - 12.0)
		)
	if quantity_modal != null:
		quantity_modal.position = Vector2(
			maxf(inset_left + TOUCH_UI_MARGIN, (viewport_size.x - quantity_modal.size.x) * 0.5),
			maxf(inset_top + 80.0, (viewport_size.y - quantity_modal.size.y) * 0.5)
		)


func _position_inventory_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var safe_insets := _get_safe_insets(viewport_size)
	var inset_left := float(safe_insets.get(&"left", 0.0))
	var inset_top := float(safe_insets.get(&"top", 0.0))
	var inset_right := float(safe_insets.get(&"right", 0.0))
	if _prefers_touch_ui():
		panel.size = Vector2(
			maxf(360.0, viewport_size.x - inset_left - inset_right - TOUCH_UI_MARGIN * 2.0),
			minf(420.0, viewport_size.y * 0.54)
		)
		panel.position = Vector2(
			inset_left + TOUCH_UI_MARGIN,
			inset_top + 78.0
		)
		return

	panel.position = Vector2(viewport_size.x, maxf(24.0, (viewport_size.y - panel.size.y) * 0.5))


func _get_safe_insets(viewport_size: Vector2) -> Dictionary:
	var safe_rect := Rect2(Vector2.ZERO, viewport_size)
	if DisplayServer.has_method("get_display_safe_area"):
		var safe_area: Variant = DisplayServer.get_display_safe_area()
		if safe_area is Rect2i:
			safe_rect = Rect2(safe_area.position, safe_area.size)
		elif safe_area is Rect2:
			safe_rect = safe_area
	return {
		&"left": maxf(0.0, safe_rect.position.x),
		&"top": maxf(0.0, safe_rect.position.y),
		&"right": maxf(0.0, viewport_size.x - safe_rect.end.x),
		&"bottom": maxf(0.0, viewport_size.y - safe_rect.end.y),
	}

func _show_mobile_action_panel(slot_index: int) -> void:
	if not _prefers_touch_ui():
		return
	selected_slot_index = slot_index
	mobile_action_panel.visible = true
	_refresh_mobile_action_panel()

func _hide_mobile_action_panel() -> void:
	mobile_action_panel.visible = false
	_pending_transfer_slot_index = -1

func _refresh_mobile_action_panel() -> void:
	if mobile_action_panel == null:
		return
	var slot_data := InventoryManager.get_slot_data(selected_slot_index)
	var has_item := StringName(slot_data.get("item_id", &"")) != &""
	selected_item_label.text = _get_tooltip_item_name(slot_data, ElementDatabase.get_element(StringName(slot_data.get("id", &""))), StringName(slot_data.get("id", &""))) if has_item else "Empty Slot"
	use_button.disabled = not has_item
	transfer_button.disabled = not has_item
	split_button.disabled = not has_item or int(slot_data.get("quantity", 0)) <= 1
	drop_button.disabled = not has_item
	details_button.disabled = not has_item
	action_hint_label.text = (
		"Tap another slot to finish the transfer."
		if _pending_transfer_slot_index >= 0 else
		"Tap a slot to equip. Long-press for details. Drag to move."
	)
	transfer_button.text = "Choose Target" if _pending_transfer_slot_index == selected_slot_index else "Transfer"

func _on_use_button_pressed() -> void:
	_select_slot(selected_slot_index, true)
	_hide_tooltip()

func _on_transfer_button_pressed() -> void:
	var slot_data := InventoryManager.get_slot_data(selected_slot_index)
	if StringName(slot_data.get("item_id", &"")) == &"":
		return
	_pending_transfer_slot_index = selected_slot_index
	_refresh_mobile_action_panel()

func _on_split_button_pressed() -> void:
	_open_quantity_modal(selected_slot_index, QuantityAction.SPLIT_DROP)

func _on_drop_button_pressed() -> void:
	var slot_data := InventoryManager.get_slot_data(selected_slot_index)
	if int(slot_data.get("quantity", 0)) <= 1:
		_try_drop_to_world(slot_data, 1)
		refresh_grid()
		return
	_open_quantity_modal(selected_slot_index, QuantityAction.DROP)

func _on_details_button_pressed() -> void:
	_show_tooltip_for_slot(selected_slot_index)

func _open_quantity_modal(slot_index: int, action: int) -> void:
	var slot_data := InventoryManager.get_slot_data(slot_index)
	var max_quantity := maxi(1, int(slot_data.get("quantity", 1)))
	_quantity_modal_slot_index = slot_index
	_quantity_modal_action = action
	_quantity_modal_value = clampi(_quantity_modal_value, 1, max_quantity)
	if _quantity_modal_value > max_quantity:
		_quantity_modal_value = max_quantity
	quantity_title_label.text = "Split Stack" if action == QuantityAction.SPLIT_DROP else "Drop Items"
	quantity_summary_label.text = "Choose how many items to drop." if action == QuantityAction.DROP else "Choose a partial stack to drop."
	quantity_confirm_button.text = "Drop"
	_update_quantity_modal()
	quantity_modal.visible = true

func _update_quantity_modal() -> void:
	var slot_data := InventoryManager.get_slot_data(_quantity_modal_slot_index)
	var max_quantity := maxi(1, int(slot_data.get("quantity", 1)))
	_quantity_modal_value = clampi(_quantity_modal_value, 1, max_quantity)
	quantity_value_label.text = "%d" % _quantity_modal_value
	quantity_minus_button.disabled = _quantity_modal_value <= 1
	quantity_plus_button.disabled = _quantity_modal_value >= max_quantity

func _adjust_quantity_modal(delta: int) -> void:
	if not quantity_modal.visible:
		return
	_quantity_modal_value += delta
	_update_quantity_modal()

func _close_quantity_modal() -> void:
	quantity_modal.visible = false
	_quantity_modal_action = QuantityAction.NONE
	_quantity_modal_slot_index = -1

func _confirm_quantity_modal() -> void:
	if _quantity_modal_slot_index < 0:
		_close_quantity_modal()
		return
	var slot_data := InventoryManager.get_slot_data(_quantity_modal_slot_index)
	_try_drop_to_world(slot_data, _quantity_modal_value)
	_close_quantity_modal()
	refresh_grid()

func _format_category(category: String) -> String:
	if category.is_empty():
		return "Unknown"

	var words := category.split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)

func _format_category_value(category_value) -> String:
	return _format_category(str(category_value))

func _get_tooltip_item_name(item_data: Dictionary, element_data: Dictionary, item_id: StringName) -> String:
	if not element_data.is_empty():
		return str(element_data.get("display_name", item_id))
	return str(item_data.get("display_name", item_id))

func _get_tooltip_item_weight(item_data: Dictionary, element_data: Dictionary) -> float:
	if not element_data.is_empty():
		return float(element_data.get("weight", item_data.get("unit_weight", 0.0)))
	return float(item_data.get("unit_weight", item_data.get("weight", 0.0)))

func _update_tooltip_durability(item_data: Dictionary) -> void:
	var durability = item_data.get("durability")
	var max_durability = item_data.get("max_durability")
	if durability == null or max_durability == null:
		tooltip_durability_label.visible = false
		return

	var max_value := maxf(float(max_durability), 0.0)
	var percent := 0
	if max_value > 0.0:
		percent = int(round(clampf(float(durability) / max_value, 0.0, 1.0) * 100.0))
	tooltip_durability_label.text = "Durability: %d%%" % percent
	tooltip_durability_label.visible = true


func _update_tooltip_hint(item_data: Dictionary, element_data: Dictionary, item_id: StringName) -> void:
	if _tooltip_hint_label == null:
		return

	var tooltip_hint := ""
	if item_id == DISTILLATION_KIT_ITEM_ID or str(item_data.get("tool_type", "")) == "distillation_kit":
		tooltip_hint = "Needed for sulfur pickup. Loses durability on use."
	elif item_id == &"iron_axe":
		tooltip_hint = "Cuts wood faster. One wood every 2 clicks."
	elif item_id == &"steel_axe":
		tooltip_hint = "Best wood tool. One wood every click."
	elif item_id == &"iron_pickaxe":
		tooltip_hint = "Mines stone and iron faster. One unit every 2 clicks."
	elif item_id == &"steel_pickaxe":
		tooltip_hint = "Best mining tool. One stone or iron every click."
	elif item_id == SULFUR_ITEM_ID:
		tooltip_hint = "Carrier risk: low HP, burning, or nearby heat can ignite carried sulfur. Move it into a Volatile Locker when you can."
	elif item_id == &"lithium":
		tooltip_hint = "Carrier risk: rain or water drains 15% charge per second. Electrical storms recharge 1% per second. Keep it dry or store it in a Dry Box."
	elif not element_data.is_empty():
		var primary_use := str(element_data.get(&"primary_use", "")).strip_edges()
		if not primary_use.is_empty():
			tooltip_hint = primary_use

	if item_id == SULFUR_ITEM_ID and WeatherSystem != null and WeatherSystem.has_method("get_current_state"):
		if int(WeatherSystem.get_current_state()) == WeatherSystem.WeatherState.ACID_MIST:
			if not tooltip_hint.is_empty():
				tooltip_hint += "\n\n"
			tooltip_hint += "[NOTICE] Acid Mist is active: exposed sulfur nodes in the world are degrading."
			
	if item_id == _carrier_risk_item_id and CarrierRiskSystem.has_method("get_active_risk_reason"):
		var active_risk_reason = CarrierRiskSystem.get_active_risk_reason(item_id)
		if not active_risk_reason.is_empty():
			if tooltip_hint.is_empty():
				tooltip_hint = "[DANGER] " + active_risk_reason
			else:
				tooltip_hint += "\n\n[DANGER] " + active_risk_reason

	_tooltip_hint_label.text = tooltip_hint
	_tooltip_hint_label.visible = not tooltip_hint.is_empty()
	if tooltip_hint.contains("[DANGER]"):
		_tooltip_hint_label.add_theme_color_override("font_color", Color.RED)
	else:
		_tooltip_hint_label.add_theme_color_override("font_color", Color(0.80, 0.84, 0.72, 1.0))


func _ensure_tooltip_hint_label() -> void:
	if _tooltip_hint_label != null:
		return
	var tooltip_content := tooltip_panel.get_node_or_null("MarginContainer/TooltipContent") as VBoxContainer
	if tooltip_content == null:
		return
	_tooltip_hint_label = Label.new()
	_tooltip_hint_label.visible = false
	_tooltip_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_hint_label.add_theme_color_override("font_color", Color(0.80, 0.84, 0.72, 1.0))
	tooltip_content.add_child(_tooltip_hint_label)

func _build_recipe_rows() -> void:
	for child in recipes_list.get_children():
		child.queue_free()
	recipe_row_refs.clear()

	var recipe_ids: Array[String] = []
	for recipe_id: StringName in RecipeDatabase.get_all_recipes().keys():
		recipe_ids.append(String(recipe_id))
	recipe_ids.sort()

	for recipe_id_text: String in recipe_ids:
		var recipe_id := StringName(recipe_id_text)
		var recipe := RecipeDatabase.get_recipe(recipe_id)
		if recipe.is_empty():
			continue
		var station_id := StringName(recipe.get(&"station", &""))
		if recipe.get(&"station", null) != null and not RecipeDatabase.is_inventory_station(station_id):
			continue

		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 88)
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = RECIPE_ROW_BG_COLOR
		row_style.border_width_left = 1
		row_style.border_width_top = 1
		row_style.border_width_right = 1
		row_style.border_width_bottom = 1
		row_style.border_color = RECIPE_ROW_BORDER_COLOR
		row_style.corner_radius_top_left = 8
		row_style.corner_radius_top_right = 8
		row_style.corner_radius_bottom_right = 8
		row_style.corner_radius_bottom_left = 8
		row.add_theme_stylebox_override("panel", row_style)
		recipes_list.add_child(row)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 10)
		row.add_child(margin)

		var card_box := VBoxContainer.new()
		card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_box.add_theme_constant_override("separation", 8)
		margin.add_child(card_box)

		var title_label := Label.new()
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_size_override("font_size", 15)
		card_box.add_child(title_label)

		var recipe_flow := HBoxContainer.new()
		recipe_flow.alignment = BoxContainer.ALIGNMENT_CENTER
		recipe_flow.add_theme_constant_override("separation", 6)
		card_box.add_child(recipe_flow)

		var locked_hint_label := Label.new()
		locked_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		locked_hint_label.visible = false
		card_box.add_child(locked_hint_label)

		var inputs: Array = recipe.get(&"inputs", [])
		for i in range(inputs.size()):
			var input_data: Dictionary = inputs[i]
			recipe_flow.add_child(_create_recipe_item_block(
				String(input_data.get(&"element_id", "")),
				int(input_data.get(&"qty", 0))
			))
			if i < inputs.size() - 1:
				recipe_flow.add_child(_create_separator_label("+"))

		recipe_flow.add_child(_create_separator_label("->"))

		var output: Dictionary = recipe.get(&"output", {})
		recipe_flow.add_child(_create_recipe_item_block(
			String(output.get(&"item_id", "")),
			int(output.get(&"qty", 0))
		))

		var details_row := HBoxContainer.new()
		details_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details_row.alignment = BoxContainer.ALIGNMENT_CENTER
		details_row.add_theme_constant_override("separation", 14)
		card_box.add_child(details_row)

		var durability_box := VBoxContainer.new()
		durability_box.custom_minimum_size = Vector2(92, 0)
		durability_box.alignment = BoxContainer.ALIGNMENT_CENTER
		details_row.add_child(durability_box)

		var durability_label := Label.new()
		durability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var durability = recipe.get(&"durability")
		if durability == null:
			durability_label.text = "Consumable"
			durability_box.add_child(durability_label)
		else:
			durability_label.text = "Durability"
			durability_box.add_child(durability_label)

			var durability_bar := ProgressBar.new()
			durability_bar.custom_minimum_size = Vector2(72, 10)
			durability_bar.max_value = 1.0
			durability_bar.show_percentage = false
			durability_bar.value = float(durability)
			durability_bar.modulate = RECIPE_DURABILITY_COLOR
			durability_box.add_child(durability_bar)

			var durability_value := Label.new()
			durability_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			durability_value.text = "%d%%" % int(round(float(durability) * 100.0))
			durability_box.add_child(durability_value)

		var availability_label := Label.new()
		availability_label.custom_minimum_size = Vector2(78, 32)
		availability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		availability_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		availability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details_row.add_child(availability_label)

		var payoff_tag_label := Label.new()
		payoff_tag_label.custom_minimum_size = Vector2(88, 26)
		payoff_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		payoff_tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		payoff_tag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		payoff_tag_label.add_theme_color_override("font_color", Color(0.91, 0.79, 0.44, 1.0))
		details_row.add_child(payoff_tag_label)

		recipe_row_refs[recipe_id] = {
			"title_label": title_label,
			"recipe_flow": recipe_flow,
			"locked_hint_label": locked_hint_label,
			"availability_label": availability_label,
			"payoff_tag_label": payoff_tag_label,
			"style": row_style,
		}

func _create_recipe_item_block(item_id: String, quantity: int) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.custom_minimum_size = Vector2(42, 0)
	block.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size = ITEM_ICON_SIZE
	block.add_child(icon_holder)

	var icon := TextureRect.new()
	icon.custom_minimum_size = ITEM_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _get_placeholder_texture(item_id)
	icon.modulate = _get_item_color(item_id)
	icon_holder.add_child(icon)

	var quantity_label := Label.new()
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_label.text = "x%d" % quantity
	block.add_child(quantity_label)

	return block

func _create_separator_label(text: String) -> Label:
	var label := Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	return label

func _refresh_recipe_states() -> void:
	for recipe_id: StringName in recipe_row_refs:
		var row_ref: Dictionary = recipe_row_refs[recipe_id]
		var title_label: Label = row_ref.get("title_label")
		var recipe_flow: HBoxContainer = row_ref.get("recipe_flow")
		var locked_hint_label: Label = row_ref.get("locked_hint_label")
		var availability_label: Label = row_ref.get("availability_label")
		var payoff_tag_label: Label = row_ref.get("payoff_tag_label")
		var row_style: StyleBoxFlat = row_ref.get("style")
		var recipe := RecipeDatabase.get_recipe(recipe_id)
		var is_unlocked := _is_recipe_unlocked(recipe)
		if title_label != null:
			title_label.text = _get_recipe_display_name(recipe_id) if is_unlocked else _get_recipe_locked_name(recipe)
		if recipe_flow != null:
			recipe_flow.visible = is_unlocked
		if locked_hint_label != null:
			locked_hint_label.visible = not is_unlocked
			locked_hint_label.text = _get_recipe_gate_hint(recipe)
		if not is_unlocked:
			availability_label.text = "Discovery\nLocked"
			availability_label.modulate = CRAFT_LOCKED_COLOR
			row_style.border_color = RECIPE_ROW_BORDER_COLOR
			if payoff_tag_label != null:
				payoff_tag_label.text = ""
				payoff_tag_label.visible = false
			continue
		var can_craft_now := CraftingManager.can_craft(recipe_id)
		availability_label.text = "Materials\nReady" if can_craft_now else "Materials\nMissing"
		availability_label.modulate = CRAFT_READY_COLOR if can_craft_now else CRAFT_LOCKED_COLOR
		row_style.border_color = CRAFT_READY_COLOR if can_craft_now else RECIPE_ROW_BORDER_COLOR
		if payoff_tag_label != null:
			var payoff_tag := _get_recipe_payoff_tag(recipe_id)
			payoff_tag_label.text = payoff_tag
			payoff_tag_label.visible = not payoff_tag.is_empty()


func _update_crafting_highlight() -> void:
	if CraftingManager.first_craft_completed or not panel.visible or not CraftingManager.has_any_craftable_recipe():
		_stop_highlight()
		return

	_start_highlight()


func _start_highlight() -> void:
	if crafting_pulse_player.is_playing():
		return

	crafting_highlight.visible = true
	var style = StyleBoxFlat.new()
	style.draw_center = false
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.border_color = CRAFT_READY_COLOR
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	crafting_highlight.add_theme_stylebox_override("panel", style)
	crafting_highlight.modulate = Color(1.0, 1.0, 1.0, 1.0)
	crafting_pulse_player.play(CRAFTING_PULSE_ANIMATION_NAME)


func _stop_highlight() -> void:
	if crafting_pulse_player.is_playing():
		crafting_pulse_player.stop()
	crafting_highlight.modulate = Color(1.0, 1.0, 1.0, 1.0)
	crafting_highlight.visible = false


func _setup_crafting_pulse_animation() -> void:
	if crafting_pulse_player.has_animation(CRAFTING_PULSE_ANIMATION_NAME):
		return

	var animation_library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.2
	animation.loop_mode = Animation.LOOP_LINEAR
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("CraftingHighlight:modulate"))
	animation.track_insert_key(track, 0.0, Color(1.0, 1.0, 1.0, 0.2))
	animation.track_insert_key(track, 0.6, Color(1.0, 1.0, 1.0, 1.0))
	animation.track_insert_key(track, 1.2, Color(1.0, 1.0, 1.0, 0.2))
	animation_library.add_animation(String(CRAFTING_PULSE_ANIMATION_NAME), animation)
	crafting_pulse_player.add_animation_library("", animation_library)


func _refresh_crafting_hint() -> void:
	if crafting_hint_label == null:
		return
	if not InventoryManager.has_item(DISTILLATION_KIT_ITEM_ID, 1):
		crafting_hint_label.text = "Next: build a Distillation Kit before sulfur runs."
		return
	if not InventoryManager.has_item(SULFUR_ITEM_ID, 1):
		crafting_hint_label.text = "Next: take the kit into Sulfur Flats for sulfur pickup."
		return
	if not InventoryManager.has_item(SULFURIC_BOLT_ITEM_ID, 1):
		crafting_hint_label.text = "Next: mix sulfur + iron at the ChemBench."
		return
	crafting_hint_label.text = "Recipes appear here. Craft buttons enable automatically when the required materials are in your inventory."


func _get_recipe_payoff_tag(recipe_id: StringName) -> String:
	match recipe_id:
		&"distillation_kit":
			return "" if InventoryManager.has_item(DISTILLATION_KIT_ITEM_ID, 1) else "Sulfur pickup"
		&"sulfuric_bolt":
			return "" if InventoryManager.has_item(SULFURIC_BOLT_ITEM_ID, 1) else "Acid ammo"
		&"rust_bolt":
			return "" if InventoryManager.has_item(RUST_BOLT_ITEM_ID, 1) or InventoryManager.has_item(DISTILLATION_KIT_ITEM_ID, 1) else "Early ammo"
		_:
			return ""


func _is_recipe_unlocked(recipe: Dictionary) -> bool:
	if DiscoveryLog != null and DiscoveryLog.has_method("is_recipe_unlocked"):
		return bool(DiscoveryLog.is_recipe_unlocked(recipe))
	return true


func _get_recipe_gate_hint(recipe: Dictionary) -> String:
	if DiscoveryLog != null and DiscoveryLog.has_method("get_recipe_gate_hint"):
		return str(DiscoveryLog.get_recipe_gate_hint(recipe))
	return ""


func _get_recipe_locked_name(recipe: Dictionary) -> String:
	if DiscoveryLog != null and DiscoveryLog.has_method("get_recipe_locked_name"):
		return str(DiscoveryLog.get_recipe_locked_name(recipe))
	return "???"


func _get_recipe_display_name(recipe_id: StringName) -> String:
	var recipe := RecipeDatabase.get_recipe(recipe_id)
	var output: Dictionary = recipe.get(&"output", {})
	var item_id := StringName(output.get(&"item_id", &""))
	if item_id.is_empty():
		return "Unknown"
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", item_id))
	var words := String(item_id).split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)

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
		"iron_axe":
			return Color(0.71, 0.73, 0.77, 1.0)
		"steel_axe":
			return Color(0.82, 0.85, 0.90, 1.0)
		"iron_pickaxe":
			return Color(0.76, 0.82, 0.88, 1.0)
		"steel_pickaxe":
			return Color(0.86, 0.90, 0.95, 1.0)
		"steel_sword":
			return Color(0.82, 0.85, 0.90, 1.0)
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
	texture.width = int(ITEM_ICON_SIZE.x)
	texture.height = int(ITEM_ICON_SIZE.y)
	_placeholder_textures[item_id] = texture
	return texture
