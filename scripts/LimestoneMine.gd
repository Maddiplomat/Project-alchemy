extends Node2D

signal limestone_mined(amount: int)

const MAX_STOCK := 30
const REGEN_RATE := 1
const REGEN_INTERVAL := 24.0
const MINE_COOLDOWN := 0.6
const HAND_MINE_PROGRESS := 0.2
const IRON_PICKAXE_PROGRESS := 0.5
const STEEL_PICKAXE_PROGRESS := 1.0
const INTERACTION_RADIUS := 52.0
const IRON_PICKAXE_ITEM_ID := &"iron_pickaxe"
const STEEL_PICKAXE_ITEM_ID := &"steel_pickaxe"
const PICKAXE_DURABILITY_LOSS := 0.05
const CLICK_TARGET_RADIUS := 28.0

var _stock := MAX_STOCK
var _mine_cooldown_remaining := 0.0
var _regen_timer := 0.0
var _player_in_range := false
var _label: Label = null
var _rocks: Array = []
var _mine_progress := 0.0


func _ready() -> void:
	add_to_group(&"scannable_resource")
	add_to_group(&"harvestable_mines")
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

	if _player_in_range and Input.is_action_just_pressed("fire_projectile") and _mine_cooldown_remaining <= 0.0 and _can_consume_attack_input():
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

	InventoryManager.add_element("limestone", yield_amount, 1.0)
	var pickaxe_item_id := mine_profile.get(&"item_id", &"") as StringName
	if not pickaxe_item_id.is_empty():
		InventoryManager.degrade_item(pickaxe_item_id, PICKAXE_DURABILITY_LOSS)
	_mine_progress = maxf(_mine_progress - float(yield_amount), 0.0)
	_stock -= yield_amount
	_mine_cooldown_remaining = MINE_COOLDOWN
	limestone_mined.emit(yield_amount)
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
	return {&"can_harvest": true, &"progress": HAND_MINE_PROGRESS, &"item_id": &""}


func _is_mouse_over_self() -> bool:
	return global_position.distance_to(get_global_mouse_position()) <= CLICK_TARGET_RADIUS


func _build_visuals() -> void:
	var ore_shapes: Array[Array] = [
		[Vector2(-16, 5), [Vector2(-13,-10), Vector2(2,-15), Vector2(13,-8), Vector2(10,6), Vector2(-6,12), Vector2(-15,2)], Color(0.70, 0.70, 0.72)],
		[Vector2(14, 0), [Vector2(-9,-9), Vector2(5,-13), Vector2(13,-2), Vector2(9,11), Vector2(-7,8)], Color(0.65, 0.65, 0.68)],
		[Vector2(-2, 11), [Vector2(-11,-6), Vector2(8,-9), Vector2(13,4), Vector2(3,11), Vector2(-12,7)], Color(0.72, 0.72, 0.75)],
		[Vector2(1, -14), [Vector2(-7,-6), Vector2(7,-9), Vector2(10,2), Vector2(4,9), Vector2(-8,5)], Color(0.68, 0.68, 0.70)],
	]

	for shape_data in ore_shapes:
		var poly := Polygon2D.new()
		poly.position = shape_data[0]
		poly.polygon = PackedVector2Array(shape_data[1])
		poly.color = shape_data[2]
		poly.z_index = 1
		add_child(poly)
		_rocks.append(poly)

	var seam1 := Line2D.new()
	seam1.default_color = Color(0.85, 0.85, 0.85, 0.9)
	seam1.width = 1.4
	seam1.z_index = 2
	seam1.points = PackedVector2Array([Vector2(-15, -2), Vector2(-5, -7), Vector2(7, -3)])
	add_child(seam1)

	var seam2 := Line2D.new()
	seam2.default_color = Color(0.80, 0.80, 0.82, 0.82)
	seam2.width = 1.2
	seam2.z_index = 2
	seam2.points = PackedVector2Array([Vector2(-1, 8), Vector2(8, 2), Vector2(16, 7)])
	add_child(seam2)

	var metallic_glint := Polygon2D.new()
	metallic_glint.polygon = PackedVector2Array([
		Vector2(-6.0, -8.0),
		Vector2(1.0, -11.0),
		Vector2(6.0, -7.0),
		Vector2(1.0, -3.0),
	])
	metallic_glint.color = Color(0.83, 0.71, 0.58, 0.35)
	metallic_glint.z_index = 3
	add_child(metallic_glint)

	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-24, 14), Vector2(24, 14), Vector2(29, 21), Vector2(-28, 21)
	])
	shadow.color = Color(0.16, 0.10, 0.09, 0.38)
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
	_label.position = Vector2(-28, -38)
	_label.z_index = 10
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.77))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	_label.visible = false
	add_child(_label)
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	if _stock <= 0:
		_label.text = "Limestone Mine\n[Depleted]"
		_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
	else:
		_label.text = "Limestone Mine  (%d)\n[Tap Attack] Mine" % _stock
		_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.87))


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player"):
		_player_in_range = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group(&"player"):
		_player_in_range = false


func get_scannable_element_id() -> StringName:
	return &"limestone"


func _flash_rocks() -> void:
	for rock in _rocks:
		if rock is Polygon2D:
			var original_color: Color = rock.color
			rock.color = Color(0.9, 0.9, 0.92)
			var timer := get_tree().create_timer(0.1)
			timer.timeout.connect(func(): rock.color = original_color)


func _show_depleted_flash() -> void:
	if _label != null:
		_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		var timer := get_tree().create_timer(0.6)
		timer.timeout.connect(func(): _refresh_label())


func _can_consume_attack_input() -> bool:
	if MobileInputRouter != null and MobileInputRouter.is_touch_mode():
		return _is_preferred_interaction_target()
	return _is_mouse_over_self()


func _is_preferred_interaction_target() -> bool:
	var player := GameManager.get_player() as Node2D
	if player == null:
		return false
	var best_node: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"harvestable_mines"):
		var harvestable := node as Node2D
		if harvestable == null:
			continue
		if not harvestable.has_method("_is_player_in_range_for_touch"):
			continue
		if not harvestable.call("_is_player_in_range_for_touch"):
			continue
		var distance := player.global_position.distance_to(harvestable.global_position)
		if distance < best_distance:
			best_distance = distance
			best_node = harvestable
	return best_node == self


func _is_player_in_range_for_touch() -> bool:
	return _player_in_range
