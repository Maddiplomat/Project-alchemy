extends CanvasLayer

@onready var panel = $InventoryPanel
@onready var grid = $InventoryPanel/PanelContent/InventoryColumn/Grid
@onready var weight_bar: ProgressBar = $InventoryPanel/PanelContent/InventoryColumn/WeightRow/WeightBar
@onready var weight_label: Label = $InventoryPanel/PanelContent/InventoryColumn/WeightRow/WeightLabel
@onready var select_keybind_label: Label = $InventoryPanel/KeybindStrip/SelectKeybindLabel
@onready var recipes_list: VBoxContainer = $InventoryPanel/PanelContent/CraftingPanel/MarginContainer/CraftingContent/RecipesScroll/RecipesList
@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_name_label: Label = $TooltipPanel/MarginContainer/TooltipContent/NameLabel
@onready var tooltip_weight_label: Label = $TooltipPanel/MarginContainer/TooltipContent/WeightLabel
@onready var tooltip_category_label: Label = $TooltipPanel/MarginContainer/TooltipContent/CategoryLabel
@onready var tooltip_durability_label: Label = $TooltipPanel/MarginContainer/TooltipContent/DurabilityLabel
@onready var crafting_highlight: Panel = $InventoryPanel/PanelContent/CraftingPanel/CraftingHighlight
@onready var crafting_pulse_player: AnimationPlayer = $InventoryPanel/PanelContent/CraftingPanel/CraftingPulsePlayer

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")
const SLOT_COUNT := 20
const TOOLTIP_DELAY := 0.3
const TOOLTIP_OFFSET := Vector2(18, 18)
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
const SELECT_KEYBIND_BASE_TEXT := "1-9: select active item"
const DRAG_QUANTITY_HINT_TEXT := "Wheel or Up/Down or Q/E to adjust qty, drag outside panel to drop"
const WORLD_DROP_DISTANCE := 22.0

var drag_origin_index := -1
var drag_ghost: TextureRect = null
var drag_source_quantity := 0
var drag_quantity := 0
var hover_slot_index := -1
var tooltip_slot_index := -1
var tooltip_delay_timer: SceneTreeTimer = null
var recipe_row_refs: Dictionary[StringName, Dictionary] = {}
var _placeholder_textures := {}
var _carrier_risk_item_id: StringName = &""

func _ready():
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
	InventoryManager.weight_changed.connect(_on_weight_changed)
	if has_node("/root/CarrierRiskSystem"):
		CarrierRiskSystem.carrier_risk_warning.connect(_on_carrier_risk_warning)
		CarrierRiskSystem.carrier_risk_cleared.connect(_on_carrier_risk_cleared)
		CarrierRiskSystem.carrier_risk_ignition.connect(_on_carrier_risk_ignition)
	_setup_crafting_pulse_animation()
	_build_recipe_rows()
	refresh_grid()
	_update_weight_display(InventoryManager.total_weight, InventoryManager.carry_capacity)
	_update_drag_hint_label()

	call_deferred("_setup_panel")

func _setup_panel():
	var vp_size = get_viewport().get_visible_rect().size
	panel.position = Vector2(vp_size.x, (vp_size.y - panel.size.y) / 2)
	panel.visible = false
	tooltip_panel.visible = false

func _input(event):
	if event.is_action_pressed("toggle_inventory"):
		if _is_inventory_toggle_blocked():
			return
		toggle_inventory()

	if _is_dragging():
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_drag_quantity(1 if not event.shift_pressed else 5)
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_drag_quantity(-1 if not event.shift_pressed else -5)
				get_viewport().set_input_as_handled()
				return

		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_UP or event.keycode == KEY_E or event.keycode == KEY_W:
				_adjust_drag_quantity(1 if not event.shift_pressed else 5)
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_DOWN or event.keycode == KEY_Q or event.keycode == KEY_S:
				_adjust_drag_quantity(-1 if not event.shift_pressed else -5)
				get_viewport().set_input_as_handled()
				return

	# Hotkeys 1-9 for slots 0-8
	for i in range(1, 10):
		if event.is_action_pressed("slot_%d" % i):
			InventoryManager.select_slot(i - 1)
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _is_dragging():
			var mouse_position := get_viewport().get_mouse_position()
			_finish_drag(_get_slot_index_at_position(mouse_position), mouse_position)

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
		_update_crafting_highlight()
	else:
		_hide_tooltip()
		_stop_highlight()

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", target_x, 0.4)

	if target_x >= vp_size.x - 1:
		# closing
		tween.tween_callback(func(): panel.visible = false)


func _is_inventory_toggle_blocked() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false
	var player := current_scene.get_node_or_null("Player")
	return player != null and player.has_method("is_input_paused") and bool(player.call("is_input_paused"))

func refresh_grid():
	var held_id = InventoryManager.get_held_item_id()
	for i in range(grid.get_child_count()):
		var slot = grid.get_child(i)
		var data = InventoryManager.get_slot_item(i)

		slot.is_equipped = (not data.is_empty() and data.id == held_id)

		if not data.is_empty():
			slot.update_slot(data.id, data.quantity, data.purity, data.get("durability"), data.get("max_durability"))
		else:
			slot.clear()
		slot.set_carrier_risk_alert(not _carrier_risk_item_id.is_empty() and not data.is_empty() and StringName(str(data.get("id", ""))) == _carrier_risk_item_id)

	if tooltip_panel.visible and hover_slot_index >= 0:
		_show_tooltip_for_slot(hover_slot_index)
	elif hover_slot_index == -1:
		_hide_tooltip()

	_refresh_recipe_states()


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
		var data = InventoryManager.get_slot_item(i)
		slot.set_carrier_risk_alert(not _carrier_risk_item_id.is_empty() and not data.is_empty() and StringName(str(data.get("id", ""))) == _carrier_risk_item_id)

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
	drag_source_quantity = int(InventoryManager.get_slot_item(slot_index).get("quantity", 0))
	drag_quantity = drag_source_quantity
	slot.set_drag_origin(true)
	_create_drag_ghost(slot)
	_update_drag_hint_label()

func _on_slot_drag_released(slot_index: int) -> void:
	if _is_dragging():
		_finish_drag(slot_index, get_viewport().get_mouse_position())

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
	var from_slot := drag_origin_index
	var quantity_to_drop := drag_quantity
	_clear_drag_ghost()
	drag_origin_index = -1
	drag_source_quantity = 0
	drag_quantity = 0
	_update_drag_hint_label()

	if from_slot >= 0 and from_slot < grid.get_child_count():
		grid.get_child(from_slot).set_drag_origin(false)

	if drop_slot_index >= 0 and drop_slot_index < grid.get_child_count() and drop_slot_index != from_slot:
		InventoryManager.swap_slots(from_slot, drop_slot_index)
		return

	if from_slot < 0:
		return

	var dragged_item := InventoryManager.get_slot_item(from_slot)
	if dragged_item.is_empty():
		return

	if _try_drop_to_station_ui(dragged_item, quantity_to_drop):
		return

	if _should_drop_to_world(release_mouse_position):
		_try_drop_to_world(dragged_item, quantity_to_drop)

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
	if select_keybind_label == null:
		return

	select_keybind_label.text = (
		"%s | %s" % [SELECT_KEYBIND_BASE_TEXT, DRAG_QUANTITY_HINT_TEXT]
		if _is_dragging() and drag_source_quantity > 1 else
		SELECT_KEYBIND_BASE_TEXT
	)


func _try_drop_to_station_ui(dragged_item: Dictionary, initial_drag_quantity: int) -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	var item_id := StringName(str(dragged_item.get("id", "")))
	var quantity := mini(initial_drag_quantity, int(dragged_item.get("quantity", 0)))
	if item_id.is_empty() or quantity <= 0:
		return false

	var mouse_position := get_viewport().get_mouse_position()
	for ui_name: String in ["FurnaceUI", "ChemBenchUI"]:
		var station_ui := current_scene.find_child(ui_name, true, false)
		if station_ui == null or not station_ui.has_method("handle_inventory_drop"):
			continue
		if not station_ui.handle_inventory_drop(mouse_position, item_id, quantity):
			continue
		return InventoryManager.remove_item(item_id, quantity)

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

	var player := current_scene.get_node_or_null("Player") as Node2D
	var spawn_system := current_scene.get_node_or_null("ElementSpawnSystem")
	if player == null or spawn_system == null or not spawn_system.has_method("spawn_inventory_pickup"):
		return false

	var pickup := spawn_system.call("spawn_inventory_pickup", dragged_item, _get_world_drop_position(player), quantity) as Node2D
	if pickup == null:
		return false

	if InventoryManager.remove_item(item_id, quantity):
		return true

	pickup.queue_free()
	return false


func _get_world_drop_position(player: Node2D) -> Vector2:
	var viewport_rect := get_viewport().get_visible_rect()
	var screen_center := viewport_rect.size * 0.5
	var direction := (get_viewport().get_mouse_position() - screen_center).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	return player.global_position + direction * WORLD_DROP_DISTANCE

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
	tooltip_name_label.text = _get_tooltip_item_name(data, element_data, item_id)
	tooltip_weight_label.text = "Weight: %.1f" % _get_tooltip_item_weight(data, element_data)
	tooltip_category_label.text = "Category: %s" % _format_category_value(data.get("category", element_data.get("category", "")))
	_update_tooltip_durability(data)
	tooltip_slot_index = slot_index
	tooltip_panel.visible = true
	_update_tooltip_position()

func _hide_tooltip() -> void:
	tooltip_delay_timer = null
	tooltip_slot_index = -1
	tooltip_panel.visible = false
	tooltip_durability_label.visible = false

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

func _format_category_value(category_value) -> String:
	if category_value is int:
		match int(category_value):
			InventoryManager.InventoryItemCategory.ELEMENT:
				return "Element"
			InventoryManager.InventoryItemCategory.TOOL:
				return "Tool"
			InventoryManager.InventoryItemCategory.CRAFTED:
				return "Crafted"
			InventoryManager.InventoryItemCategory.CONSUMABLE:
				return "Consumable"
			_:
				return "Generic"
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

		var row_box := HBoxContainer.new()
		row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		row_box.add_theme_constant_override("separation", 10)
		margin.add_child(row_box)

		var recipe_flow := HBoxContainer.new()
		recipe_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		recipe_flow.add_theme_constant_override("separation", 6)
		row_box.add_child(recipe_flow)

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

		var durability_box := VBoxContainer.new()
		durability_box.custom_minimum_size = Vector2(82, 0)
		durability_box.alignment = BoxContainer.ALIGNMENT_CENTER
		row_box.add_child(durability_box)

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
		availability_label.custom_minimum_size = Vector2(96, 32)
		availability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		availability_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		availability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_box.add_child(availability_label)

		recipe_row_refs[recipe_id] = {
			"availability_label": availability_label,
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
		var availability_label: Label = row_ref.get("availability_label")
		var row_style: StyleBoxFlat = row_ref.get("style")
		var can_craft_now := CraftingManager.can_craft(recipe_id)
		availability_label.text = "Materials\nReady" if can_craft_now else "Materials\nMissing"
		availability_label.modulate = CRAFT_READY_COLOR if can_craft_now else CRAFT_LOCKED_COLOR
		row_style.border_color = CRAFT_READY_COLOR if can_craft_now else RECIPE_ROW_BORDER_COLOR


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
		"primitive_axe":
			return Color(0.76, 0.82, 0.88, 1.0)
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
