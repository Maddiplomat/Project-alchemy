class_name TreeResource
extends StaticBody2D

signal depleted(tree: TreeResource)

const MAX_WOOD := 10
const INTERACTION_RADIUS := 52.0
const HAND_HARVEST_PROGRESS := 0.2
const IRON_AXE_PROGRESS := 0.5
const STEEL_AXE_PROGRESS := 1.0
const IRON_AXE_ITEM_ID := &"iron_axe"
const STEEL_AXE_ITEM_ID := &"steel_axe"
const AXE_DURABILITY_LOSS := 0.05
const TREE_COLOR := Color(0.18, 0.44, 0.20, 1.0)
const TREE_HIGHLIGHT_COLOR := Color(0.28, 0.58, 0.29, 1.0)
const TRUNK_COLOR := Color(0.43, 0.27, 0.14, 1.0)
const SHADOW_COLOR := Color(0.08, 0.11, 0.08, 0.28)
const HEALTH_BAR_FULL_COLOR := Color(0.47, 0.82, 0.39, 1.0)
const HEALTH_BAR_MID_COLOR := Color(0.86, 0.71, 0.22, 1.0)
const HEALTH_BAR_LOW_COLOR := Color(0.86, 0.29, 0.22, 1.0)
const CLICK_TARGET_RADIUS := 18.0

@export var tile_coords := Vector2i.ZERO
@export_range(1, MAX_WOOD, 1) var remaining_wood := MAX_WOOD

@onready var canopy: Polygon2D = $Canopy
@onready var trunk: Polygon2D = $Trunk
@onready var shadow: Polygon2D = $Shadow
@onready var health_bar_bg: Panel = $HealthBarBg
@onready var health_bar_fill: ColorRect = $HealthBarBg/HealthBarFill

var _player: Node2D = null
var _health_bar_fill_max_width := 0.0
var _harvest_progress := 0.0


func _ready() -> void:
	input_pickable = true
	add_to_group(&"harvestable_trees")
	add_to_group(&"scannable_resource")
	_build_visuals()
	_health_bar_fill_max_width = health_bar_fill.size.x
	_refresh_health_bar()


func _process(_delta: float) -> void:
	_player = _resolve_player()
	health_bar_bg.visible = _should_show_prompt()
	if health_bar_bg.visible and Input.is_action_just_pressed("fire_projectile") and _is_mouse_over_tree():
		_harvest()


func configure(coords: Vector2i, stock: int = MAX_WOOD) -> void:
	tile_coords = coords
	remaining_wood = clampi(stock, 1, MAX_WOOD)
	_harvest_progress = 0.0
	if is_node_ready():
		_refresh_health_bar()


func export_state() -> Dictionary:
	return {
		&"tile_coords": {
			&"x": tile_coords.x,
			&"y": tile_coords.y,
		},
		&"remaining_wood": remaining_wood,
		&"harvest_progress": _harvest_progress,
	}

func _harvest() -> bool:
	if remaining_wood <= 0:
		return false
	if not _should_show_prompt():
		return false

	var yield_profile := _get_yield_profile()
	if not bool(yield_profile.get(&"can_harvest", false)):
		return false

	_harvest_progress += float(yield_profile.get(&"progress", 0.0))
	var amount := mini(int(floor(_harvest_progress)), remaining_wood)
	if amount <= 0:
		return false
	if not InventoryManager.add_element("wood", amount, 1.0):
		return false

	var axe_item_id := yield_profile.get(&"item_id", &"") as StringName
	if not axe_item_id.is_empty():
		InventoryManager.degrade_item(axe_item_id, AXE_DURABILITY_LOSS)

	_harvest_progress = maxf(_harvest_progress - float(amount), 0.0)
	remaining_wood -= amount
	GameManager.mark_dirty()
	if remaining_wood <= 0:
		_harvest_progress = 0.0
		health_bar_bg.visible = false
		depleted.emit(self)
	else:
		_refresh_health_bar()
	return true


func _get_yield_profile() -> Dictionary:
	var held_item := InventoryManager.get_held_item()
	if held_item.is_empty():
		return {&"can_harvest": true, &"progress": HAND_HARVEST_PROGRESS, &"item_id": &""}

	var held_item_id := StringName(str(held_item.get("id", "")))
	match held_item_id:
		IRON_AXE_ITEM_ID:
			return {&"can_harvest": true, &"progress": IRON_AXE_PROGRESS, &"item_id": held_item_id}
		STEEL_AXE_ITEM_ID:
			return {&"can_harvest": true, &"progress": STEEL_AXE_PROGRESS, &"item_id": held_item_id}
		_:
			return {&"can_harvest": true, &"progress": HAND_HARVEST_PROGRESS, &"item_id": &""}


func _can_player_harvest() -> bool:
	if remaining_wood <= 0:
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	return global_position.distance_to(_player.global_position) <= INTERACTION_RADIUS


func _should_show_prompt() -> bool:
	if BuildSystem != null and BuildSystem.is_build_mode_active():
		return false
	if not _can_player_harvest():
		return false
	return _is_preferred_interaction_target()


func _is_preferred_interaction_target() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var best_tree: TreeResource = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"harvestable_trees"):
		var tree := node as TreeResource
		if tree == null or not is_instance_valid(tree):
			continue
		if not tree._can_player_harvest():
			continue
		var distance := tree.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best_tree = tree
	return best_tree == self


func _resolve_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var player_nodes := get_tree().get_nodes_in_group(&"player")
	if player_nodes.is_empty():
		return null
	return player_nodes[0] as Node2D


func get_scannable_element_id() -> StringName:
	return &"wood"


func _refresh_health_bar() -> void:
	if health_bar_fill == null:
		return
	var ratio := clampf(float(remaining_wood) / float(MAX_WOOD), 0.0, 1.0)
	health_bar_fill.size.x = _health_bar_fill_max_width * ratio
	health_bar_fill.color = _get_health_bar_color(ratio)


func _get_health_bar_color(ratio: float) -> Color:
	if ratio <= 0.3:
		return HEALTH_BAR_LOW_COLOR
	if ratio <= 0.6:
		return HEALTH_BAR_MID_COLOR
	return HEALTH_BAR_FULL_COLOR


func _is_mouse_over_tree() -> bool:
	return global_position.distance_to(get_global_mouse_position()) <= CLICK_TARGET_RADIUS


func _build_visuals() -> void:
	canopy.polygon = PackedVector2Array([
		Vector2(-12.0, -6.0),
		Vector2(-7.0, -17.0),
		Vector2(2.0, -20.0),
		Vector2(11.0, -15.0),
		Vector2(14.0, -5.0),
		Vector2(8.0, 5.0),
		Vector2(-8.0, 7.0),
		Vector2(-15.0, 0.0),
	])
	canopy.color = TREE_COLOR
	var highlight := PackedVector2Array([
		Vector2(-7.0, -11.0),
		Vector2(1.0, -16.0),
		Vector2(7.0, -12.0),
		Vector2(3.0, -6.0),
		Vector2(-5.0, -5.0),
	])
	var highlight_node := Polygon2D.new()
	highlight_node.polygon = highlight
	highlight_node.color = TREE_HIGHLIGHT_COLOR
	highlight_node.z_index = canopy.z_index + 1
	add_child(highlight_node)

	trunk.polygon = PackedVector2Array([
		Vector2(-3.0, -2.0),
		Vector2(3.0, -2.0),
		Vector2(4.0, 11.0),
		Vector2(-4.0, 11.0),
	])
	trunk.color = TRUNK_COLOR
	shadow.polygon = PackedVector2Array([
		Vector2(-10.0, 10.0),
		Vector2(9.0, 10.0),
		Vector2(13.0, 14.0),
		Vector2(-14.0, 14.0),
	])
	shadow.color = SHADOW_COLOR
