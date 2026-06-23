extends Node

signal buildable_placed(buildable_id: StringName)

const DEFAULT_GHOST_SIZE := Vector2i(32, 32)
const GHOST_VALID_COLOR := Color(0.36, 0.92, 0.48, 0.6)
const GHOST_INVALID_COLOR := Color(0.92, 0.28, 0.24, 0.6)
const PLACED_OBJECT_GROUP := &"placed_objects"
const BUILD_MENU_PANEL_SIZE := Vector2(456.0, 420.0)
const SHELTER_COVER_RADIUS_TILES := 1
const SHELTER_COVER_VALID_COLOR := Color(0.38, 0.76, 0.98, 0.26)
const SHELTER_COVER_INVALID_COLOR := Color(0.98, 0.54, 0.22, 0.22)
const SHELTER_SUPPORT_OK_COLOR := Color(0.36, 0.92, 0.48, 0.76)
const SHELTER_SUPPORT_MISSING_COLOR := Color(0.92, 0.28, 0.24, 0.76)

@export var selected_prefab: PackedScene
@export var selected_buildable_id: StringName = &"wall"
@export var build_mode := false

var _buildable_ids: Array[StringName] = []
var _selected_prefab_index := 0
var _ghost: Sprite2D = null
var _build_menu_layer: CanvasLayer = null
var _build_menu_panel: PanelContainer = null
var _build_menu_title: Label = null
var _build_menu_hint: Label = null
var _build_menu_buildables_text: RichTextLabel = null
var _ghost_texture: Texture2D = null
var _placement_shape: Shape2D = null
var _placement_shape_transform := Transform2D.IDENTITY
var _placement_sprite_offset := Vector2.ZERO
var _selected_rotation_degrees := 0.0
var _last_tile_coords := Vector2i.ZERO
var _last_world_position := Vector2.ZERO
var _last_placement_valid := false
var _restore_data: Dictionary = {}
var _shelter_preview_root: Node2D = null
var _shelter_coverage_markers: Array[Sprite2D] = []
var _shelter_support_markers: Array[Sprite2D] = []
var _preview_tile_texture: Texture2D = null
var _dynamic_build_hint := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_prefab_configuration()
	_ensure_build_menu()
	if has_node("/root/InventoryManager"):
		InventoryManager.inventory_changed.connect(_refresh_build_menu.unbind(1))
	if has_node("/root/DiscoveryLog"):
		DiscoveryLog.discovery_made.connect(func(_entry: Dictionary) -> void: _refresh_build_menu())
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

		if key_event.keycode == KEY_R:
			_rotate_selected_prefab()
			get_viewport().set_input_as_handled()
			return

	if not build_mode:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if _is_pointer_over_build_menu():
				return
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


func enter_build_mode_for_existing(scene_path: String, restore_data: Variant = null) -> void:
	# Find the matching buildable ID by scene path
	var target_id: StringName = &""
	for bid: StringName in _get_buildable_order_source():
		var prefab: PackedScene = _get_buildable_entry(bid).get(&"prefab") as PackedScene
		if prefab != null and prefab.resource_path == scene_path:
			target_id = bid
			break
	if target_id.is_empty():
		return
	# Store restore payload so _place_selected_prefab skips cost and applies it after
	if restore_data is Dictionary:
		_restore_data = (restore_data as Dictionary).duplicate(true)
	elif restore_data is float and float(restore_data) >= 0.0:
		_restore_data = {&"burn_time_remaining": float(restore_data)}
	else:
		_restore_data = {}
	_select_prefab_by_id(target_id)
	_selected_rotation_degrees = float(_restore_data.get(&"placed_rotation_degrees", 0.0)) if _is_selected_buildable_rotatable() else 0.0
	_enter_build_mode()


func _select_prefab_by_id(buildable_id: StringName) -> void:
	_ensure_prefab_configuration()
	var idx := _buildable_ids.find(buildable_id)
	if idx == -1:
		return
	_select_prefab_by_index(idx)


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
		_dynamic_build_hint = ""
		if is_instance_valid(_ghost):
			_ghost.visible = false
		_hide_shelter_preview()
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
	if not _is_selected_buildable_rotatable():
		_selected_rotation_degrees = 0.0
	_cache_prefab_preview_data()
	_refresh_build_menu()
	if is_instance_valid(_ghost):
		_ghost.texture = _ghost_texture
		_ghost.offset = _placement_sprite_offset
		_ghost.rotation_degrees = _selected_rotation_degrees


func _rotate_selected_prefab() -> void:
	if not build_mode or not _is_selected_buildable_rotatable():
		return
	_selected_rotation_degrees = fposmod(_selected_rotation_degrees + 90.0, 180.0)
	if is_instance_valid(_ghost):
		_ghost.rotation_degrees = _selected_rotation_degrees
	_refresh_build_menu()


func _ensure_prefab_configuration() -> void:
	_buildable_ids.clear()
	for buildable_id: StringName in _get_buildable_order_source():
		if _has_buildable(buildable_id) and _is_buildable_unlocked(buildable_id):
			_buildable_ids.append(buildable_id)

	if _buildable_ids.is_empty():
		selected_buildable_id = &""
		selected_prefab = null
		return

	if selected_buildable_id.is_empty() or not _has_buildable(selected_buildable_id) or not _is_buildable_unlocked(selected_buildable_id):
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
	_ghost.rotation_degrees = _selected_rotation_degrees
	_ghost.modulate = GHOST_VALID_COLOR if _last_placement_valid else GHOST_INVALID_COLOR
	_ghost.visible = true
	_update_shelter_preview(context, tile_coords, _last_placement_valid)
	_update_dynamic_build_hint(context, tile_coords)


func _is_valid_placement(context: Dictionary, tile_coords: Vector2i, world_position: Vector2) -> bool:
	if selected_prefab == null:
		return false

	var ground := context.get(&"ground") as TileMapLayer
	var objects := context.get(&"objects") as TileMapLayer
	var scene_root := context.get(&"scene") as Node2D
	var is_overlay := _selected_buildable_is_overlay()
	if ground == null:
		return false

	for occupied_offset: Vector2i in _get_selected_buildable_occupied_offsets():
		var occupied_tile := tile_coords + occupied_offset
		if ground.get_cell_source_id(occupied_tile) == -1:
			return false
		if objects != null and objects.get_cell_source_id(occupied_tile) != -1:
			return false
		if not is_overlay and _has_placed_object_at_tile(context.get(&"scene") as Node, occupied_tile):
			return false
		if is_overlay and _has_anchor_object_at_tile(context.get(&"scene") as Node, occupied_tile, selected_buildable_id):
			return false
		
	if selected_buildable_id == &"shelter_roof" and not _has_shelter_roof_support(context.get(&"scene") as Node, tile_coords):
		return false

	if is_overlay:
		return true

	if _placement_shape == null:
		return false

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _placement_shape
	query.transform = Transform2D(deg_to_rad(_selected_rotation_degrees), world_position) * _placement_shape_transform
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1

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


func import_from_world_save_data(world_save_data) -> void:
	if world_save_data == null:
		return

	var context := _get_build_context()
	var scene_root := context.get(&"scene") as Node
	var ground := context.get(&"ground") as TileMapLayer
	if scene_root == null or ground == null:
		return

	for node in get_tree().get_nodes_in_group(PLACED_OBJECT_GROUP):
		if is_instance_valid(node):
			node.queue_free()

	_instantiate_saved_entries(world_save_data.placed_stations, scene_root, ground)
	_instantiate_saved_entries(world_save_data.walls, scene_root, ground)
	_instantiate_saved_entries(world_save_data.storage, scene_root, ground)


func _has_placed_object_at_tile(scene_root: Node, tile_coords: Vector2i) -> bool:
	if scene_root == null:
		return false

	for node in get_tree().get_nodes_in_group(PLACED_OBJECT_GROUP):
		if not is_instance_valid(node):
			continue
		if scene_root != node and not scene_root.is_ancestor_of(node):
			continue
		if node.has_method("get_occupied_tile_coords"):
			var occupied_tiles: Array = node.call("get_occupied_tile_coords")
			if occupied_tiles.has(tile_coords):
				return true
			continue
		if node.has_meta(&"build_tile_coords") and node.get_meta(&"build_tile_coords") == tile_coords:
			return true

	return false


func _has_anchor_object_at_tile(scene_root: Node, tile_coords: Vector2i, object_type: StringName = &"") -> bool:
	if scene_root == null:
		return false

	for node in get_tree().get_nodes_in_group(PLACED_OBJECT_GROUP):
		if not is_instance_valid(node):
			continue
		if scene_root != node and not scene_root.is_ancestor_of(node):
			continue
		if not node.has_meta(&"build_tile_coords") or node.get_meta(&"build_tile_coords") != tile_coords:
			continue
		if object_type.is_empty():
			return true
		var node_object_type := StringName(str(node.get_meta(&"object_type", "")))
		if node_object_type == object_type:
			return true

	return false


func _get_selected_buildable_occupied_offsets() -> Array[Vector2i]:
	if selected_buildable_id == &"electric_trap":
		var normalized_rotation := posmod(int(round(_selected_rotation_degrees)), 180)
		if normalized_rotation == 90:
			return [Vector2i(0, -1), Vector2i.ZERO, Vector2i(0, 1)]
		return [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
	return [Vector2i.ZERO]


func _selected_buildable_is_overlay() -> bool:
	if selected_buildable_id.is_empty() or not _has_buildable(selected_buildable_id):
		return false
	return bool(_get_buildable_entry(selected_buildable_id).get(&"overlay", false))


func _has_shelter_roof_support(scene_root: Node, tile_coords: Vector2i) -> bool:
	return _count_shelter_roof_supports(scene_root, tile_coords) >= 2


func _count_shelter_roof_supports(scene_root: Node, tile_coords: Vector2i) -> int:
	if scene_root == null:
		return 0

	var support_count := 0
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if _has_structural_support_at_tile(scene_root, tile_coords + offset):
			support_count += 1
	return support_count


func _has_structural_support_at_tile(scene_root: Node, tile_coords: Vector2i) -> bool:
	for node in get_tree().get_nodes_in_group(PLACED_OBJECT_GROUP):
		if not is_instance_valid(node):
			continue
		if scene_root != node and not scene_root.is_ancestor_of(node):
			continue
		if not node.has_meta(&"build_tile_coords") or node.get_meta(&"build_tile_coords") != tile_coords:
			continue
		var object_type := StringName(str(node.get_meta(&"object_type", "")))
		if object_type == &"wall" or object_type == &"door":
			return true
	return false


func _place_selected_prefab() -> void:
	if not _last_placement_valid or selected_prefab == null:
		return

	# Only deduct cost when NOT in "re-place existing" mode
	if _restore_data.is_empty():
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
	placed_node.rotation_degrees = _selected_rotation_degrees if _is_selected_buildable_rotatable() else 0.0
	if placed_node.has_method("configure_placed_object"):
		placed_node.call("configure_placed_object", _last_tile_coords)
	else:
		placed_node.add_to_group(PLACED_OBJECT_GROUP)
		placed_node.set_meta(&"placed_object", true)
		placed_node.set_meta(&"build_tile_coords", _last_tile_coords)
		placed_node.set_meta(&"object_type", String(selected_buildable_id))

	# Restore saved state (e.g. campfire burn time) when re-placing an existing object
	if not _restore_data.is_empty():
		if placed_node.has_method("restore_from_pickup"):
			placed_node.call("restore_from_pickup", _restore_data)
		_restore_data = {}

	buildable_placed.emit(selected_buildable_id)
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
	_ghost.rotation_degrees = _selected_rotation_degrees
	current_scene.add_child(_ghost)


func _ensure_shelter_preview() -> void:
	if is_instance_valid(_shelter_preview_root):
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	if _preview_tile_texture == null:
		_preview_tile_texture = _build_preview_tile_texture()

	_shelter_preview_root = Node2D.new()
	_shelter_preview_root.name = "ShelterPreview"
	_shelter_preview_root.z_index = 4095
	current_scene.add_child(_shelter_preview_root)

	_shelter_coverage_markers.clear()
	for _i in range(9):
		var coverage_marker := Sprite2D.new()
		coverage_marker.texture = _preview_tile_texture
		coverage_marker.visible = false
		_shelter_preview_root.add_child(coverage_marker)
		_shelter_coverage_markers.append(coverage_marker)

	_shelter_support_markers.clear()
	for _i in range(4):
		var support_marker := Sprite2D.new()
		support_marker.texture = _preview_tile_texture
		support_marker.scale = Vector2(0.55, 0.55)
		support_marker.visible = false
		_shelter_preview_root.add_child(support_marker)
		_shelter_support_markers.append(support_marker)


func _hide_shelter_preview() -> void:
	if not is_instance_valid(_shelter_preview_root):
		return
	for marker in _shelter_coverage_markers:
		marker.visible = false
	for marker in _shelter_support_markers:
		marker.visible = false


func _update_shelter_preview(context: Dictionary, tile_coords: Vector2i, placement_valid: bool) -> void:
	if selected_buildable_id != &"shelter_roof":
		_hide_shelter_preview()
		return

	_ensure_shelter_preview()
	if not is_instance_valid(_shelter_preview_root):
		return

	var ground := context.get(&"ground") as TileMapLayer
	var scene_root := context.get(&"scene") as Node
	if ground == null or scene_root == null:
		_hide_shelter_preview()
		return

	var coverage_color := SHELTER_COVER_VALID_COLOR if placement_valid else SHELTER_COVER_INVALID_COLOR
	var coverage_index := 0
	for y in range(-SHELTER_COVER_RADIUS_TILES, SHELTER_COVER_RADIUS_TILES + 1):
		for x in range(-SHELTER_COVER_RADIUS_TILES, SHELTER_COVER_RADIUS_TILES + 1):
			var coverage_tile := tile_coords + Vector2i(x, y)
			var coverage_marker := _shelter_coverage_markers[coverage_index]
			coverage_marker.global_position = ground.to_global(ground.map_to_local(coverage_tile))
			coverage_marker.modulate = coverage_color
			coverage_marker.visible = true
			coverage_index += 1

	var support_offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for support_index in range(support_offsets.size()):
		var support_tile: Vector2i = tile_coords + support_offsets[support_index]
		var support_marker := _shelter_support_markers[support_index]
		support_marker.global_position = ground.to_global(ground.map_to_local(support_tile))
		support_marker.modulate = SHELTER_SUPPORT_OK_COLOR \
			if _has_structural_support_at_tile(scene_root, support_tile) \
			else SHELTER_SUPPORT_MISSING_COLOR
		support_marker.visible = true


func _update_dynamic_build_hint(context: Dictionary, tile_coords: Vector2i) -> void:
	_dynamic_build_hint = ""
	if selected_buildable_id == &"shelter_roof":
		var support_count := _count_shelter_roof_supports(context.get(&"scene") as Node, tile_coords)
		_dynamic_build_hint = (
			"Shelter Roof covers a 3x3 area. Needs 2 adjacent walls or doors. "
			+ "Support near cursor: %d/2." % support_count
		)
	if _build_menu_hint != null:
		_build_menu_hint.text = _build_hint_text()


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
	_build_menu_panel.custom_minimum_size = BUILD_MENU_PANEL_SIZE
	_build_menu_panel.offset_right = 16.0 + BUILD_MENU_PANEL_SIZE.x
	_build_menu_panel.offset_bottom = 16.0 + BUILD_MENU_PANEL_SIZE.y
	_build_menu_layer.add_child(_build_menu_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_build_menu_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	_build_menu_title = Label.new()
	_build_menu_title.add_theme_font_size_override("font_size", 20)
	content.add_child(_build_menu_title)

	_build_menu_hint = Label.new()
	_build_menu_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_build_menu_hint)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.selection_enabled = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	_build_menu_buildables_text = text


func _refresh_build_menu() -> void:
	if _build_menu_title == null or _build_menu_hint == null:
		return

	_build_menu_title.text = "Build Mode"
	_build_menu_hint.text = _build_hint_text()

	if _build_menu_buildables_text != null:
		_build_menu_buildables_text.text = _build_buildables_text()


func _get_selected_buildable_prefab() -> PackedScene:
	if selected_buildable_id.is_empty() or not _has_buildable(selected_buildable_id):
		return null
	return _get_buildable_entry(selected_buildable_id).get(&"prefab") as PackedScene


func _get_selected_buildable_cost() -> Dictionary:
	return _get_buildable_cost(selected_buildable_id)


func _get_buildable_cost(buildable_id: StringName) -> Dictionary:
	if buildable_id.is_empty() or not _has_buildable(buildable_id):
		return {}
	return (_get_buildable_entry(buildable_id).get(&"cost", {}) as Dictionary).duplicate(true)


func _get_buildable_display_name(buildable_id: StringName) -> String:
	if buildable_id.is_empty() or not _has_buildable(buildable_id):
		return "Unknown"
	return String(_get_buildable_entry(buildable_id).get(&"label", String(buildable_id).capitalize()))


func _is_selected_buildable_rotatable() -> bool:
	if selected_buildable_id.is_empty() or not _has_buildable(selected_buildable_id):
		return false
	return bool(_get_buildable_entry(selected_buildable_id).get(&"rotatable", false))


func _instantiate_saved_entries(entries: Array, scene_root: Node, ground: TileMapLayer) -> void:
	for entry_variant in entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var scene_path := str(entry.get(&"scene_path", ""))
		if scene_path.is_empty():
			continue
		var packed_scene := load(scene_path) as PackedScene
		if packed_scene == null:
			continue

		var placed_object := packed_scene.instantiate()
		if not (placed_object is Node2D):
			if placed_object != null:
				placed_object.free()
			continue

		var placed_node := placed_object as Node2D
		var tile_coords := Vector2i.ZERO
		var tile_coords_variant: Variant = entry.get(&"placed_at", Vector2i.ZERO)
		if tile_coords_variant is Vector2i:
			tile_coords = tile_coords_variant
		scene_root.add_child(placed_node)
		placed_node.global_position = ground.to_global(ground.map_to_local(tile_coords))
		placed_node.rotation_degrees = float(entry.get(&"placed_rotation_degrees", 0.0))
		if placed_node.has_method("configure_placed_object"):
			placed_node.call("configure_placed_object", tile_coords)
		if placed_node.has_method("restore_from_pickup"):
			placed_node.call("restore_from_pickup", entry)


func _get_buildable_order_source() -> Array[StringName]:
	if BuildingDatabase != null and BuildingDatabase.has_method("get_buildable_order"):
		return BuildingDatabase.get_buildable_order()
	return []


func _has_buildable(buildable_id: StringName) -> bool:
	if BuildingDatabase != null and BuildingDatabase.has_method("has_buildable"):
		return bool(BuildingDatabase.has_buildable(buildable_id))
	return false


func _get_buildable_entry(buildable_id: StringName) -> Dictionary:
	if BuildingDatabase != null and BuildingDatabase.has_method("get_buildable_entry"):
		return BuildingDatabase.get_buildable_entry(buildable_id)
	return {}


func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"

	var parts: Array[String] = []
	for item_id: StringName in cost.keys():
		parts.append("%s x%d" % [_format_resource_name(item_id), int(cost[item_id])])
	parts.sort()
	return ", ".join(parts)


func _build_buildables_text() -> String:
	var lines: Array[String] = [
		"Placeables",
		"",
	]

	var ordered_ids := _get_buildable_order_source()
	if ordered_ids.is_empty():
		lines.append("No buildables configured.")
		return "\n".join(lines)

	var current_category := &""
	for buildable_id: StringName in ordered_ids:
		if not _has_buildable(buildable_id):
			continue
		var category_id := StringName(_get_buildable_entry(buildable_id).get(&"category", &""))
		if category_id != current_category:
			if not current_category.is_empty():
				lines.append("")
			current_category = category_id
			lines.append(_get_buildable_category_label(category_id))
			lines.append("")

		var is_unlocked := _is_buildable_unlocked(buildable_id)
		var is_selected := is_unlocked and _buildable_ids.find(buildable_id) == _selected_prefab_index
		var cost := _get_buildable_cost(buildable_id)
		var display_name := _get_buildable_display_name(buildable_id) if is_unlocked else _get_buildable_locked_name(buildable_id)
		lines.append("%s%s" % ["> " if is_selected else "  ", display_name])
		if is_unlocked:
			lines.append("  Cost: %s" % _format_cost(cost))
			var description := _get_buildable_description(buildable_id)
			if not description.is_empty():
				lines.append("  %s" % description)
			if bool(_get_buildable_entry(buildable_id).get(&"overlay", false)):
				lines.append("  Placement: overlay")
			if bool(_get_buildable_entry(buildable_id).get(&"rotatable", false)):
				if is_selected:
					lines.append("  Rotation: %d degrees (R rotates)" % int(round(_selected_rotation_degrees)))
				else:
					lines.append("  Rotation: rotatable")
			lines.append("  Status: %s" % ("Ready to place" if _can_afford_cost(cost) else "Missing materials"))
		else:
			lines.append("  Locked: %s" % _get_buildable_gate_hint(buildable_id))
		lines.append("")

	return "\n".join(lines)


func _is_buildable_unlocked(buildable_id: StringName) -> bool:
	if BuildingDatabase != null and BuildingDatabase.has_method("is_buildable_unlocked"):
		return bool(BuildingDatabase.is_buildable_unlocked(buildable_id))
	return true


func _get_buildable_category_label(category_id: StringName) -> String:
	if BuildingDatabase != null and BuildingDatabase.has_method("get_category_label"):
		return str(BuildingDatabase.get_category_label(category_id))
	return String(category_id).capitalize()


func _get_buildable_description(buildable_id: StringName) -> String:
	return str(_get_buildable_entry(buildable_id).get(&"description", ""))


func _get_buildable_gate_hint(buildable_id: StringName) -> String:
	if BuildingDatabase != null and BuildingDatabase.has_method("get_buildable_gate_hint"):
		return str(BuildingDatabase.get_buildable_gate_hint(buildable_id))
	return ""


func _get_buildable_locked_name(buildable_id: StringName) -> String:
	if BuildingDatabase != null and BuildingDatabase.has_method("get_buildable_locked_name"):
		return str(BuildingDatabase.get_buildable_locked_name(buildable_id))
	return "???"


func _format_resource_name(item_id: StringName) -> String:
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", item_id))
	var words := String(item_id).split("_", false)
	for index in range(words.size()):
		words[index] = words[index].capitalize()
	return " ".join(words)


func _is_pointer_over_build_menu() -> bool:
	return is_instance_valid(_build_menu_panel) and _build_menu_panel.get_global_rect().has_point(get_viewport().get_mouse_position())


func _can_afford_cost(cost: Dictionary) -> bool:
	for item_id: StringName in cost.keys():
		if InventoryManager.get_stack(item_id).quantity < int(cost[item_id]):
			return false
	return true


func _deduct_build_cost(cost: Dictionary) -> bool:
	for item_id: StringName in cost.keys():
		InventoryManager.remove_element(item_id, int(cost[item_id]))
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


func _build_hint_text() -> String:
	if not _dynamic_build_hint.is_empty():
		return _dynamic_build_hint
	if selected_buildable_id == &"shelter_roof":
		return "B or Esc closes. Tab cycles buildables. Shelter Roof covers a 3x3 area and needs 2 adjacent walls or doors."
	return "B or Esc closes. Tab cycles buildables. Recipes live in the pack UI and field journal, not in the build menu."


func _build_preview_tile_texture() -> Texture2D:
	var image := Image.create(DEFAULT_GHOST_SIZE.x, DEFAULT_GHOST_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	for y in range(DEFAULT_GHOST_SIZE.y):
		for x in range(DEFAULT_GHOST_SIZE.x):
			var is_border := x <= 1 or y <= 1 or x >= DEFAULT_GHOST_SIZE.x - 2 or y >= DEFAULT_GHOST_SIZE.y - 2
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if is_border else 0.72))
	return ImageTexture.create_from_image(image)
