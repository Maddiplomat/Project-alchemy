extends Node

const BUILDABLE_ORDER: Array[StringName] = [
	&"wall",
	&"door",
	&"furnace",
	&"chem_bench",
	&"campfire",
	&"storage_chest",
]
const BUILDABLE_REGISTRY := {
	&"wall": {
		&"prefab": preload("res://scenes/Wall.tscn"),
		&"cost": {&"stone": 2},
		&"label": "Wall",
	},
	&"door": {
		&"prefab": preload("res://scenes/Door.tscn"),
		&"cost": {&"wood": 1, &"stone": 1},
		&"label": "Door",
	},
	&"furnace": {
		&"prefab": preload("res://scenes/FurnacePlaced.tscn"),
		&"cost": {&"iron": 3, &"stone": 2},
		&"label": "Furnace",
	},
	&"chem_bench": {
		&"prefab": preload("res://scenes/ChemBenchPlaced.tscn"),
		&"cost": {&"iron": 4, &"wood": 2},
		&"label": "Chem Bench",
	},
	&"campfire": {
		&"prefab": preload("res://scenes/Campfire.tscn"),
		&"cost": {&"wood": 5},
		&"label": "Campfire",
	},
	&"storage_chest": {
		&"prefab": preload("res://scenes/StorageChest.tscn"),
		&"cost": {&"wood": 4},
		&"label": "Storage Chest",
	},
}
const DEFAULT_GHOST_SIZE := Vector2i(32, 32)
const GHOST_VALID_COLOR := Color(0.36, 0.92, 0.48, 0.6)
const GHOST_INVALID_COLOR := Color(0.92, 0.28, 0.24, 0.6)
const PLACED_OBJECT_GROUP := &"placed_objects"

@export var selected_prefab: PackedScene
@export var selected_buildable_id: StringName = &"wall"
@export var build_mode := false

var _buildable_ids: Array[StringName] = []
var _selected_prefab_index := 0
var _ghost: Sprite2D = null
var _build_menu_layer: CanvasLayer = null
var _build_menu_panel: PanelContainer = null
var _build_menu_label: Label = null
var _ghost_texture: Texture2D = null
var _placement_shape: Shape2D = null
var _placement_shape_transform := Transform2D.IDENTITY
var _placement_sprite_offset := Vector2.ZERO
var _last_tile_coords := Vector2i.ZERO
var _last_world_position := Vector2.ZERO
var _last_placement_valid := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_prefab_configuration()
	_ensure_build_menu()
	_select_prefab_by_index(_selected_prefab_index)
	_set_build_mode(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_B:
			if build_mode:
				_exit_build_mode()
			else:
				_enter_build_mode()
			get_viewport().set_input_as_handled()
			return

		if not build_mode:
			return

		if key_event.keycode == KEY_ESCAPE:
			_exit_build_mode()
			get_viewport().set_input_as_handled()
			return

		if key_event.keycode == KEY_TAB:
			_cycle_selected_prefab()
			get_viewport().set_input_as_handled()
			return

	if not build_mode:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if _last_placement_valid:
				_place_selected_prefab()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not build_mode:
		return

	var context := _get_build_context()
	if context.is_empty():
		_exit_build_mode()
		return

	_update_build_preview(context)


func is_build_mode_active() -> bool:
	return build_mode


func _enter_build_mode() -> void:
	_ensure_prefab_configuration()
	if selected_prefab == null:
		return
	if _get_build_context().is_empty():
		return
	_set_build_mode(true)
	_update_build_preview(_get_build_context())


func _exit_build_mode() -> void:
	_set_build_mode(false)


func _set_build_mode(enabled: bool) -> void:
	build_mode = enabled
	if not enabled:
		_last_placement_valid = false
		if is_instance_valid(_ghost):
			_ghost.visible = false
		if is_instance_valid(_build_menu_layer):
			_build_menu_layer.visible = false
		return

	_ensure_ghost()
	_refresh_build_menu()
	if is_instance_valid(_ghost):
		_ghost.visible = true
	if is_instance_valid(_build_menu_layer):
		_build_menu_layer.visible = true


func _cycle_selected_prefab() -> void:
	_ensure_prefab_configuration()
	if _buildable_ids.is_empty():
		return
	_select_prefab_by_index((_selected_prefab_index + 1) % _buildable_ids.size())


func _select_prefab_by_index(index: int) -> void:
	_ensure_prefab_configuration()
	if _buildable_ids.is_empty():
		selected_buildable_id = &""
		selected_prefab = null
		return

	_selected_prefab_index = posmod(index, _buildable_ids.size())
	selected_buildable_id = _buildable_ids[_selected_prefab_index]
	selected_prefab = _get_selected_buildable_prefab()
	_cache_prefab_preview_data()
	_refresh_build_menu()
	if is_instance_valid(_ghost):
		_ghost.texture = _ghost_texture
		_ghost.offset = _placement_sprite_offset


func _ensure_prefab_configuration() -> void:
	_buildable_ids.clear()
	for buildable_id: StringName in BUILDABLE_ORDER:
		if BUILDABLE_REGISTRY.has(buildable_id):
			_buildable_ids.append(buildable_id)

	if _buildable_ids.is_empty():
		selected_buildable_id = &""
		selected_prefab = null
		return

	if selected_buildable_id.is_empty() or not BUILDABLE_REGISTRY.has(selected_buildable_id):
		selected_buildable_id = _buildable_ids[0]

	_selected_prefab_index = maxi(_buildable_ids.find(selected_buildable_id), 0)
	selected_prefab = _get_selected_buildable_prefab()


func _get_build_context() -> Dictionary:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return {}

	var ground := current_scene.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return {}

	return {
		&"scene": current_scene,
		&"ground": ground,
		&"objects": current_scene.get_node_or_null("Objects") as TileMapLayer,
	}


func _update_build_preview(context: Dictionary) -> void:
	_ensure_ghost()
	if _ghost == null:
		return

	var ground := context.get(&"ground") as TileMapLayer
	var mouse_world := ground.get_global_mouse_position()
	var tile_coords := ground.local_to_map(ground.to_local(mouse_world))
	var snapped_world_position := ground.to_global(ground.map_to_local(tile_coords))

	_last_tile_coords = tile_coords
	_last_world_position = snapped_world_position
	_last_placement_valid = _is_valid_placement(context, tile_coords, snapped_world_position)

	_ghost.global_position = snapped_world_position
	_ghost.modulate = GHOST_VALID_COLOR if _last_placement_valid else GHOST_INVALID_COLOR
	_ghost.visible = true


func _is_valid_placement(context: Dictionary, tile_coords: Vector2i, world_position: Vector2) -> bool:
	if selected_prefab == null:
		return false

	var ground := context.get(&"ground") as TileMapLayer
	if ground == null or ground.get_cell_source_id(tile_coords) == -1:
		return false

	var objects := context.get(&"objects") as TileMapLayer
	if objects != null and objects.get_cell_source_id(tile_coords) != -1:
		return false

	if _has_placed_object_at_tile(context.get(&"scene") as Node, tile_coords):
		return false

	if _placement_shape == null:
		return false

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _placement_shape
	query.transform = Transform2D(0.0, world_position) * _placement_shape_transform
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1

	var scene_root := context.get(&"scene") as Node2D
	if scene_root == null:
		return false
	var world_2d: World2D = scene_root.get_world_2d()
	if world_2d == null:
		return false

	for hit in world_2d.direct_space_state.intersect_shape(query, 16):
		var collider := hit.get("collider") as Node
		if collider == null or collider == ground:
			continue
		return false

	return true


func export_to_world_save_data(world_save_data) -> void:
	if world_save_data == null:
		return

	world_save_data.clear_placed_objects()
	for node in get_tree().get_nodes_in_group(PLACED_OBJECT_GROUP):
		if not is_instance_valid(node):
			continue
		if node.has_method("export_to_world_save_data"):
			node.call("export_to_world_save_data", world_save_data)
	if has_node("/root/StorageManager"):
		StorageManager.export_to_world_save_data(world_save_data)


func build_world_save_data():
	export_to_world_save_data(WorldSaveData)
	return WorldSaveData


func _has_placed_object_at_tile(scene_root: Node, tile_coords: Vector2i) -> bool:
	if scene_root == null:
		return false

	for node in get_tree().get_nodes_in_group(PLACED_OBJECT_GROUP):
		if not is_instance_valid(node):
			continue
		if scene_root != node and not scene_root.is_ancestor_of(node):
			continue
		if node.has_meta(&"build_tile_coords") and node.get_meta(&"build_tile_coords") == tile_coords:
			return true

	return false


func _place_selected_prefab() -> void:
	if not _last_placement_valid or selected_prefab == null:
		return

	var build_cost := _get_selected_buildable_cost()
	if not _can_afford_cost(build_cost):
		return
	if not _deduct_build_cost(build_cost):
		return

	var context := _get_build_context()
	var scene_root := context.get(&"scene") as Node
	if scene_root == null:
		return

	var placed_object := selected_prefab.instantiate()
	if not (placed_object is Node2D):
		placed_object.free()
		return

	scene_root.add_child(placed_object)
	var placed_node := placed_object as Node2D
	placed_node.global_position = _last_world_position
	if placed_node.has_method("configure_placed_object"):
		placed_node.call("configure_placed_object", _last_tile_coords)
	else:
		placed_node.add_to_group(PLACED_OBJECT_GROUP)
		placed_node.set_meta(&"placed_object", true)
		placed_node.set_meta(&"build_tile_coords", _last_tile_coords)
		placed_node.set_meta(&"object_type", String(selected_buildable_id))
	GameManager.mark_dirty()


func _ensure_ghost() -> void:
	if is_instance_valid(_ghost):
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	_ghost = Sprite2D.new()
	_ghost.name = "BuildGhost"
	_ghost.z_index = 4096
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.modulate = GHOST_INVALID_COLOR
	_ghost.texture = _ghost_texture if _ghost_texture != null else _build_default_ghost_texture()
	current_scene.add_child(_ghost)


func _cache_prefab_preview_data() -> void:
	_ghost_texture = _build_default_ghost_texture()
	_placement_shape = RectangleShape2D.new()
	(_placement_shape as RectangleShape2D).size = Vector2(DEFAULT_GHOST_SIZE)
	_placement_shape_transform = Transform2D.IDENTITY
	_placement_sprite_offset = Vector2.ZERO

	if selected_prefab == null:
		return

	var preview_instance := selected_prefab.instantiate()
	if preview_instance == null:
		return

	var sprite := _find_sprite_2d(preview_instance)
	if sprite != null and sprite.texture != null:
		_ghost_texture = sprite.texture
		_placement_sprite_offset = sprite.offset

	var collision_shape := _find_collision_shape_2d(preview_instance)
	if collision_shape != null and collision_shape.shape != null:
		_placement_shape = collision_shape.shape.duplicate(true)
		_placement_shape_transform = collision_shape.transform

	preview_instance.free()


func _find_sprite_2d(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var found := _find_sprite_2d(child)
		if found != null:
			return found
	return null


func _find_collision_shape_2d(node: Node) -> CollisionShape2D:
	if node.has_node("CollisionShape2D"):
		return node.get_node("CollisionShape2D") as CollisionShape2D
	for child in node.get_children():
		var found := _find_collision_shape_2d(child)
		if found != null:
			return found
	return null


func _ensure_build_menu() -> void:
	if is_instance_valid(_build_menu_layer):
		return

	_build_menu_layer = CanvasLayer.new()
	_build_menu_layer.name = "BuildMenu"
	add_child(_build_menu_layer)

	_build_menu_panel = PanelContainer.new()
	_build_menu_panel.offset_left = 16.0
	_build_menu_panel.offset_top = 16.0
	_build_menu_panel.offset_right = 248.0
	_build_menu_panel.offset_bottom = 132.0
	_build_menu_layer.add_child(_build_menu_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_build_menu_panel.add_child(margin)

	_build_menu_label = Label.new()
	_build_menu_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_build_menu_label)


func _refresh_build_menu() -> void:
	if _build_menu_label == null:
		return

	var lines: Array[String] = [
		"Build Mode",
		"B / Esc: Cancel",
		"Tab: Cycle Buildable",
	]

	if _buildable_ids.is_empty():
		lines.append("No buildables configured")
	else:
		for i in range(_buildable_ids.size()):
			var marker := "> " if i == _selected_prefab_index else "  "
			var buildable_id := _buildable_ids[i]
			lines.append("%s%s (%s)" % [
				marker,
				_get_buildable_display_name(buildable_id),
				_format_cost(_get_buildable_cost(buildable_id)),
			])

	_build_menu_label.text = "\n".join(lines)


func _get_selected_buildable_prefab() -> PackedScene:
	if selected_buildable_id.is_empty() or not BUILDABLE_REGISTRY.has(selected_buildable_id):
		return null
	return BUILDABLE_REGISTRY[selected_buildable_id].get(&"prefab") as PackedScene


func _get_selected_buildable_cost() -> Dictionary:
	return _get_buildable_cost(selected_buildable_id)


func _get_buildable_cost(buildable_id: StringName) -> Dictionary:
	if buildable_id.is_empty() or not BUILDABLE_REGISTRY.has(buildable_id):
		return {}
	return (BUILDABLE_REGISTRY[buildable_id].get(&"cost", {}) as Dictionary).duplicate(true)


func _get_buildable_display_name(buildable_id: StringName) -> String:
	if buildable_id.is_empty() or not BUILDABLE_REGISTRY.has(buildable_id):
		return "Unknown"
	return String(BUILDABLE_REGISTRY[buildable_id].get(&"label", String(buildable_id).capitalize()))


func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"

	var parts: Array[String] = []
	for item_id: StringName in cost.keys():
		parts.append("%s x%d" % [String(item_id).capitalize(), int(cost[item_id])])
	parts.sort()
	return ", ".join(parts)


func _can_afford_cost(cost: Dictionary) -> bool:
	for item_id: StringName in cost.keys():
		if not InventoryManager.has_item(item_id, int(cost[item_id])):
			return false
	return true


func _deduct_build_cost(cost: Dictionary) -> bool:
	for item_id: StringName in cost.keys():
		if not InventoryManager.remove_item(item_id, int(cost[item_id])):
			return false
	return true


func _build_default_ghost_texture() -> Texture2D:
	var image := Image.create(DEFAULT_GHOST_SIZE.x, DEFAULT_GHOST_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	for y in range(DEFAULT_GHOST_SIZE.y):
		for x in range(DEFAULT_GHOST_SIZE.x):
			var is_border := x == 0 or y == 0 or x == DEFAULT_GHOST_SIZE.x - 1 or y == DEFAULT_GHOST_SIZE.y - 1
			if is_border:
				image.set_pixel(x, y, Color(0.08, 0.08, 0.08, 1.0))
	return ImageTexture.create_from_image(image)
