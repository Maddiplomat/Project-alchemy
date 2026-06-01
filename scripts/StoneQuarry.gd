extends Node2D

signal stone_mined(amount: int)

const MAX_STOCK := 30
const REGEN_RATE := 1           # stone per regen tick
const REGEN_INTERVAL := 20.0    # seconds between regen ticks
const MINE_COOLDOWN := 0.5      # seconds between clicks
const HAND_MINE_PROGRESS := 0.2
const IRON_PICKAXE_PROGRESS := 0.5
const STEEL_PICKAXE_PROGRESS := 1.0
const INTERACTION_RADIUS := 48.0
const IRON_PICKAXE_ITEM_ID := &"iron_pickaxe"
const STEEL_PICKAXE_ITEM_ID := &"steel_pickaxe"
const PICKAXE_DURABILITY_LOSS := 0.05

var _stock := MAX_STOCK
var _mine_cooldown_remaining := 0.0
var _regen_timer := 0.0
var _player_in_range := false
var _label: Label = null
var _rocks: Array = []
var _mine_progress := 0.0


func _ready() -> void:
	_build_visuals()
	_build_interaction_area()
	_build_label()


func _process(delta: float) -> void:
	_mine_cooldown_remaining = maxf(0.0, _mine_cooldown_remaining - delta)

	_regen_timer += delta
	if _regen_timer >= REGEN_INTERVAL:
		_regen_timer = 0.0
		_stock = mini(_stock + REGEN_RATE, MAX_STOCK)
		_refresh_label()

	if _player_in_range and Input.is_action_just_pressed("fire_projectile") and _mine_cooldown_remaining <= 0.0:
		_do_mine()


func _do_mine() -> void:
	if _stock <= 0:
		_show_depleted_flash()
		return

	if not _can_harvest_with_held_item():
		return

	var mine_profile := _get_mine_profile()
	_mine_progress += float(mine_profile.get(&"progress", 0.0))
	var yield_amount := mini(int(floor(_mine_progress)), _stock)
	if yield_amount <= 0:
		return

	InventoryManager.add_element("stone", yield_amount, 1.0)
	var pickaxe_item_id := mine_profile.get(&"item_id", &"") as StringName
	if not pickaxe_item_id.is_empty():
		InventoryManager.degrade_item(pickaxe_item_id, PICKAXE_DURABILITY_LOSS)
	_mine_progress = maxf(_mine_progress - float(yield_amount), 0.0)
	_stock -= yield_amount
	_mine_cooldown_remaining = MINE_COOLDOWN
	stone_mined.emit(yield_amount)
	_flash_rocks()
	_refresh_label()


func _can_harvest_with_held_item() -> bool:
	return bool(_get_mine_profile().get(&"can_harvest", false))


func _get_mine_profile() -> Dictionary:
	var held_item := InventoryManager.get_held_item()
	if held_item.is_empty():
		return {&"can_harvest": true, &"progress": HAND_MINE_PROGRESS, &"item_id": &""}
	var held_item_id := StringName(str(held_item.get("id", "")))
	if held_item_id == IRON_PICKAXE_ITEM_ID:
		return {&"can_harvest": true, &"progress": IRON_PICKAXE_PROGRESS, &"item_id": held_item_id}
	if held_item_id == STEEL_PICKAXE_ITEM_ID:
		return {&"can_harvest": true, &"progress": STEEL_PICKAXE_PROGRESS, &"item_id": held_item_id}
	if int(held_item.get("category", InventoryManager.InventoryItemCategory.GENERIC)) == InventoryManager.InventoryItemCategory.ELEMENT:
		return {&"can_harvest": true, &"progress": HAND_MINE_PROGRESS, &"item_id": &""}
	return {&"can_harvest": false, &"progress": 0.0, &"item_id": &""}


func _build_visuals() -> void:
	# Main quarry face — several large grey-brown polygon rocks
	var rock_shapes: Array[Array] = [
		# [offset, polygon points, color]
		[Vector2(-18, 4), [Vector2(-12,-10), Vector2(4,-14), Vector2(14,-6), Vector2(10,8), Vector2(-8,10), Vector2(-14,2)], Color(0.48, 0.46, 0.44)],
		[Vector2(14, 0), [Vector2(-8,-8), Vector2(6,-12), Vector2(12,-2), Vector2(8,10), Vector2(-6,8)], Color(0.44, 0.42, 0.40)],
		[Vector2(-4, 10), [Vector2(-10,-6), Vector2(8,-8), Vector2(12,4), Vector2(4,10), Vector2(-12,6)], Color(0.52, 0.50, 0.47)],
		[Vector2(2, -14), [Vector2(-6,-6), Vector2(6,-8), Vector2(10,2), Vector2(4,8), Vector2(-8,4)], Color(0.56, 0.53, 0.50)],
	]

	for shape_data in rock_shapes:
		var poly := Polygon2D.new()
		poly.position = shape_data[0]
		poly.polygon = PackedVector2Array(shape_data[1])
		poly.color = shape_data[2]
		poly.z_index = 1
		add_child(poly)
		_rocks.append(poly)

	# Highlight vein lines for mineral appearance
	var vein1 := Line2D.new()
	vein1.default_color = Color(0.70, 0.68, 0.65, 0.7)
	vein1.width = 1.2
	vein1.z_index = 2
	vein1.points = PackedVector2Array([Vector2(-14, -2), Vector2(-4, -6), Vector2(6, -4)])
	add_child(vein1)

	var vein2 := Line2D.new()
	vein2.default_color = Color(0.62, 0.60, 0.57, 0.6)
	vein2.width = 1.0
	vein2.z_index = 2
	vein2.points = PackedVector2Array([Vector2(2, 8), Vector2(10, 2), Vector2(16, 6)])
	add_child(vein2)

	# Shadow base
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-22, 14), Vector2(22, 14), Vector2(26, 20), Vector2(-26, 20)
	])
	shadow.color = Color(0.20, 0.18, 0.16, 0.35)
	shadow.z_index = 0
	add_child(shadow)


func _build_interaction_area() -> void:
	var area := Area2D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = INTERACTION_RADIUS
	shape.shape = circle
	area.add_child(shape)
	add_child(area)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _build_label() -> void:
	_label = Label.new()
	_label.position = Vector2(-32, -36)
	_label.z_index = 10
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	_label.visible = false
	add_child(_label)
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	if _stock <= 0:
		_label.text = "Stone Quarry\n[Depleted]"
		_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.5))
	else:
		var key_hint := "Left Click"
		_label.text = "Stone Quarry  (%d)\n[%s] Mine" % [_stock, key_hint]
		_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))


func _has_mine_action_key() -> bool:
	return InputMap.has_action("mine")


func _get_mine_action_key() -> String:
	if InputMap.has_action("mine"):
		var events := InputMap.action_get_events("mine")
		if not events.is_empty():
			return events[0].as_text()
	return "Z"


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player"):
		_player_in_range = true
		if _label != null:
			_label.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group(&"player"):
		_player_in_range = false
		if _label != null:
			_label.visible = false


func _flash_rocks() -> void:
	for rock in _rocks:
		if rock is Polygon2D:
			var original_color: Color = rock.color
			rock.color = Color(0.80, 0.78, 0.75)
			var timer := get_tree().create_timer(0.1)
			timer.timeout.connect(func(): rock.color = original_color)


func _show_depleted_flash() -> void:
	if _label != null:
		_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		var timer := get_tree().create_timer(0.6)
		timer.timeout.connect(func(): _refresh_label())
