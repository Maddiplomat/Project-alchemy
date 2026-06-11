extends Node

const BUILDABLE_ORDER: Array[StringName] = [
	&"wall",
	&"door",
	&"furnace",
	&"chem_bench",
	&"campfire",
	&"storage_chest",
	&"powered_light_post",
	&"electric_trap",
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
	&"powered_light_post": {
		&"prefab": preload("res://scenes/PoweredLightPost.tscn"),
		&"cost": {&"iron": 1, &"energy_cell": 1},
		&"label": "Powered Light",
	},
	&"electric_trap": {
		&"prefab": preload("res://scenes/ElectricTrap.tscn"),
		&"cost": {&"iron": 2, &"lithium": 1, &"energy_cell": 1},
		&"label": "Electric Trap",
		&"rotatable": true,
	},
}
const DEFAULT_GHOST_SIZE := Vector2i(32, 32)
const GHOST_VALID_COLOR := Color(0.36, 0.92, 0.48, 0.6)
const GHOST_INVALID_COLOR := Color(0.92, 0.28, 0.24, 0.6)
const PLACED_OBJECT_GROUP := &"placed_objects"
const BUILD_MENU_PANEL_SIZE := Vector2(472.0, 548.0)
const BUILD_MENU_SECTION_ORDER: Array[StringName] = [&"buildables", &"tools", &"weapons", &"smelting"]
const BUILD_MENU_TAB_TITLES := {
	&"buildables": "Build",
	&"tools": "Tools",
	&"weapons": "Weapons",
	&"smelting": "Smelting",
}
const MANUAL_RECIPE_DEFINITIONS := {
	&"iron_axe": {
		&"display_name": "Iron Axe",
		&"station": "Furnace Forge",
		&"inputs": [{&"item_id": &"iron", &"qty": 2}, {&"item_id": &"wood", &"qty": 2}],
		&"summary": "Forged harvesting axe. Cuts wood faster than hand gathering.",
	},
	&"steel_axe": {
		&"display_name": "Steel Axe",
		&"station": "Furnace Forge",
		&"inputs": [{&"item_id": &"steel", &"qty": 2}, {&"item_id": &"wood", &"qty": 2}],
		&"summary": "Best axe tier. Delivers one wood per chop.",
		&"discovery_gate": {
			&"entry_id": &"steel",
			&"hint": "Discover Steel in the furnace to unlock advanced forge patterns.",
			&"locked_name": "???",
		},
	},
	&"iron_pickaxe": {
		&"display_name": "Iron Pickaxe",
		&"station": "Furnace Forge",
		&"inputs": [{&"item_id": &"iron", &"qty": 2}, {&"item_id": &"wood", &"qty": 2}],
		&"summary": "Forged mining tool for stone, iron, and limestone.",
	},
	&"steel_pickaxe": {
		&"display_name": "Steel Pickaxe",
		&"station": "Furnace Forge",
		&"inputs": [{&"item_id": &"steel", &"qty": 2}, {&"item_id": &"wood", &"qty": 2}],
		&"summary": "Best mining tier. Delivers one unit per swing.",
		&"discovery_gate": {
			&"entry_id": &"steel",
			&"hint": "Discover Steel in the furnace to unlock advanced forge patterns.",
			&"locked_name": "???",
		},
	},
	&"steel_sword": {
		&"display_name": "Steel Sword",
		&"station": "Furnace Forge",
		&"inputs": [{&"item_id": &"steel", &"qty": 1}],
		&"summary": "Primary melee weapon. Reliable physical sharp damage.",
		&"discovery_gate": {
			&"entry_id": &"steel",
			&"hint": "Discover Steel in the furnace to unlock advanced forge patterns.",
			&"locked_name": "???",
		},
	},
	&"charcoal": {
		&"display_name": "Charcoal",
		&"station": "Furnace Smelt",
		&"inputs": [{&"item_id": &"wood", &"qty": 1}],
		&"summary": "Carbonise wood at 400-699C for furnace-grade carbon.",
	},
	&"slag": {
		&"display_name": "Slag",
		&"station": "Furnace Smelt",
		&"inputs": [{&"item_id": &"wood", &"qty": 1}],
		&"summary": "Overburn result. At 700C or above wood collapses into slag.",
	},
	&"wrought_iron": {
		&"display_name": "Wrought Iron",
		&"station": "Furnace Smelt",
		&"inputs": [{&"item_id": &"iron", &"qty": 1}, {&"item_id": &"charcoal", &"qty": 1}],
		&"summary": "Smelt at 1200-1599C with low carbon ratio under 0.5.",
	},
	&"steel": {
		&"display_name": "Steel",
		&"station": "Furnace Smelt",
		&"inputs": [{&"item_id": &"iron", &"qty": 1}, {&"item_id": &"charcoal", &"qty": 1}],
		&"summary": "Optimal alloy window: 1200-1599C with carbon ratio from 0.5 to 2.1.",
	},
	&"cast_iron": {
		&"display_name": "Cast Iron",
		&"station": "Furnace Smelt",
		&"inputs": [{&"item_id": &"iron", &"qty": 1}, {&"item_id": &"charcoal", &"qty": 1}],
		&"summary": "High-carbon result. Use 1200-1599C with ratio above 2.1 up to 4.5.",
	},
	&"coke_slag": {
		&"display_name": "Coke Slag",
		&"station": "Furnace Smelt",
		&"inputs": [{&"item_id": &"iron", &"qty": 1}, {&"item_id": &"charcoal", &"qty": 2}],
		&"summary": "Waste output when carbon overwhelms the iron above a 4.5 ratio.",
	},
}

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
var _build_menu_tabs: TabContainer = null
var _build_menu_buildables_text: RichTextLabel = null
var _build_menu_section_lists: Dictionary[StringName, VBoxContainer] = {}
var _ghost_texture: Texture2D = null
var _placement_shape: Shape2D = null
var _placement_shape_transform := Transform2D.IDENTITY
var _placement_sprite_offset := Vector2.ZERO
var _selected_rotation_degrees := 0.0
var _last_tile_coords := Vector2i.ZERO
var _last_world_position := Vector2.ZERO
var _last_placement_valid := false
var _restore_data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_prefab_configuration()
	_ensure_build_menu()
	if has_node("/root/InventoryManager"):
		InventoryManager.inventory_changed.connect(_refresh_build_menu)
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
	for bid: StringName in BUILDABLE_REGISTRY:
		var prefab: PackedScene = BUILDABLE_REGISTRY[bid].get(&"prefab")
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
	_ghost.rotation_degrees = _selected_rotation_degrees
	_ghost.modulate = GHOST_VALID_COLOR if _last_placement_valid else GHOST_INVALID_COLOR
	_ghost.visible = true


func _is_valid_placement(context: Dictionary, tile_coords: Vector2i, world_position: Vector2) -> bool:
	if selected_prefab == null:
		return false

	var ground := context.get(&"ground") as TileMapLayer
	var objects := context.get(&"objects") as TileMapLayer
	if ground == null:
		return false

	for occupied_offset: Vector2i in _get_selected_buildable_occupied_offsets():
		var occupied_tile := tile_coords + occupied_offset
		if ground.get_cell_source_id(occupied_tile) == -1:
			return false
		if objects != null and objects.get_cell_source_id(occupied_tile) != -1:
			return false
		if _has_placed_object_at_tile(context.get(&"scene") as Node, occupied_tile):
			return false

	if _placement_shape == null:
		return false

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _placement_shape
	query.transform = Transform2D(deg_to_rad(_selected_rotation_degrees), world_position) * _placement_shape_transform
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

	for entry_variant in world_save_data.placed_stations:
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
		if node.has_meta(&"build_tile_coords") and node.get_meta(&"build_tile_coords") == tile_coords:
			return true

	return false


func _get_selected_buildable_occupied_offsets() -> Array[Vector2i]:
	if selected_buildable_id == &"electric_trap":
		var normalized_rotation := posmod(int(round(_selected_rotation_degrees)), 180)
		if normalized_rotation == 90:
			return [Vector2i(0, -1), Vector2i.ZERO, Vector2i(0, 1)]
		return [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
	return [Vector2i.ZERO]


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

	_build_menu_tabs = TabContainer.new()
	_build_menu_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_build_menu_tabs)

	for section_id: StringName in BUILD_MENU_SECTION_ORDER:
		var scroll := ScrollContainer.new()
		scroll.name = str(BUILD_MENU_TAB_TITLES.get(section_id, String(section_id).capitalize()))
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_build_menu_tabs.add_child(scroll)

		if section_id == &"buildables":
			var text := RichTextLabel.new()
			text.bbcode_enabled = false
			text.fit_content = true
			text.scroll_active = false
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.selection_enabled = false
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(text)
			_build_menu_buildables_text = text
		else:
			var list := VBoxContainer.new()
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.add_theme_constant_override("separation", 8)
			scroll.add_child(list)
			_build_menu_section_lists[section_id] = list


func _refresh_build_menu() -> void:
	if _build_menu_title == null or _build_menu_hint == null:
		return

	_build_menu_title.text = "Build Mode"
	_build_menu_hint.text = "B or Esc closes. Tab cycles placeables. Recipes live here now; station lines tell you where each one is made."

	if _build_menu_buildables_text != null:
		_build_menu_buildables_text.text = _build_buildables_text()

	for section_id: StringName in _build_menu_section_lists.keys():
		var section_list: VBoxContainer = _build_menu_section_lists[section_id]
		if section_list == null:
			continue
		_populate_recipe_section(section_id, section_list)


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


func _is_selected_buildable_rotatable() -> bool:
	if selected_buildable_id.is_empty() or not BUILDABLE_REGISTRY.has(selected_buildable_id):
		return false
	return bool(BUILDABLE_REGISTRY[selected_buildable_id].get(&"rotatable", false))


func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"

	var parts: Array[String] = []
	for item_id: StringName in cost.keys():
		parts.append("%s x%d" % [String(item_id).capitalize(), int(cost[item_id])])
	parts.sort()
	return ", ".join(parts)


func _build_buildables_text() -> String:
	var lines: Array[String] = [
		"Placeables",
		"",
	]

	if _buildable_ids.is_empty():
		lines.append("No buildables configured.")
		return "\n".join(lines)

	for i in range(_buildable_ids.size()):
		var buildable_id := _buildable_ids[i]
		var is_selected := i == _selected_prefab_index
		var cost := _get_buildable_cost(buildable_id)
		lines.append("%s%s" % ["> " if is_selected else "  ", _get_buildable_display_name(buildable_id)])
		lines.append("  Cost: %s" % _format_cost(cost))
		if is_selected and _is_selected_buildable_rotatable():
			lines.append("  Rotation: %d degrees (R rotates)" % int(round(_selected_rotation_degrees)))
		lines.append("  Status: %s" % ("Ready to place" if _can_afford_cost(cost) else "Missing materials"))
		lines.append("")

	return "\n".join(lines)


func _populate_recipe_section(section_id: StringName, section_list: VBoxContainer) -> void:
	for child in section_list.get_children():
		child.queue_free()

	var entries := _get_recipe_browser_entries(section_id)
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No entries."
		section_list.add_child(empty_label)
		return

	for entry: Dictionary in entries:
		section_list.add_child(_create_recipe_entry_card(entry))


func _get_recipe_browser_entries(section_id: StringName) -> Array[Dictionary]:
	match section_id:
		&"tools":
			return _get_tool_recipe_entries()
		&"weapons":
			return _get_weapon_recipe_entries()
		&"smelting":
			return _get_smelting_recipe_entries()
		_:
			return []


func _get_tool_recipe_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var distillation_recipe := _get_recipe_entry_from_database(&"distillation_kit")
	if not distillation_recipe.is_empty():
		entries.append(distillation_recipe)
	for output_id: StringName in [&"iron_axe", &"steel_axe", &"iron_pickaxe", &"steel_pickaxe"]:
		entries.append(_get_manual_recipe_entry(output_id))
	return entries


func _get_weapon_recipe_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for recipe_id: StringName in [&"rust_bolt", &"sulfuric_bolt", &"corrosive_slurry"]:
		var recipe_entry := _get_recipe_entry_from_database(recipe_id)
		if not recipe_entry.is_empty():
			entries.append(recipe_entry)
	entries.append(_get_manual_recipe_entry(&"steel_sword"))
	return entries


func _get_smelting_recipe_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for output_id: StringName in [&"charcoal", &"slag", &"wrought_iron", &"steel", &"cast_iron", &"coke_slag"]:
		entries.append(_get_manual_recipe_entry(output_id))
	return entries


func _get_recipe_entry_from_database(recipe_id: StringName) -> Dictionary:
	var recipe := RecipeDatabase.get_recipe(recipe_id)
	if recipe.is_empty():
		return {}

	var output: Dictionary = recipe.get(&"output", {})
	var output_id: StringName = output.get(&"item_id", &"")
	var station_id: StringName = &""
	if recipe.get(&"station", null) != null:
		station_id = StringName(recipe.get(&"station", &""))
	var is_unlocked := _is_recipe_unlocked(recipe)
	var entry := {
		&"recipe_id": recipe_id,
		&"display_name": _get_database_recipe_display_name(recipe_id, output_id),
		&"station_id": station_id,
		&"station": _get_station_label(station_id),
		&"inputs": (recipe.get(&"inputs", []) as Array).duplicate(true),
		&"output_id": output_id,
		&"output_qty": int(output.get(&"qty", 1)),
		&"summary": _get_database_recipe_summary(recipe_id),
		&"status_text": "Use station" if not station_id.is_empty() else ("Ready now" if CraftingManager.can_craft(recipe_id) else "Missing materials"),
		&"can_execute_from_menu": station_id.is_empty(),
		&"is_unlocked": is_unlocked,
		&"locked_name": _get_locked_name(recipe),
		&"locked_hint": _get_recipe_gate_hint(recipe),
	}
	return entry


func _get_manual_recipe_entry(output_id: StringName) -> Dictionary:
	var recipe: Dictionary = MANUAL_RECIPE_DEFINITIONS.get(output_id, {})
	if recipe.is_empty():
		return {}

	var inputs: Array = recipe.get(&"inputs", [])
	var is_unlocked := _is_recipe_unlocked(recipe)
	return {
		&"recipe_id": &"",
		&"display_name": str(recipe.get(&"display_name", _format_item_name(output_id))),
		&"station_id": StringName(str(recipe.get(&"station", ""))),
		&"station": str(recipe.get(&"station", "")),
		&"inputs": inputs.duplicate(true),
		&"output_id": output_id,
		&"output_qty": 1,
		&"summary": str(recipe.get(&"summary", "")),
		&"status_text": "Use station" if _has_required_inputs(inputs) else "Missing materials",
		&"can_execute_from_menu": false,
		&"is_unlocked": is_unlocked,
		&"locked_name": _get_locked_name(recipe),
		&"locked_hint": _get_recipe_gate_hint(recipe),
	}


func _has_required_inputs(inputs: Array) -> bool:
	for input_data in inputs:
		if not (input_data is Dictionary):
			return false
		var item_id: StringName = input_data.get(&"item_id", input_data.get(&"element_id", &""))
		var quantity := int(input_data.get(&"qty", input_data.get(&"quantity", 0)))
		if item_id.is_empty() or quantity <= 0:
			return false
		if not InventoryManager.has_item(item_id, quantity):
			return false
	return true


func _format_recipe_inputs(inputs: Array) -> String:
	var parts: Array[String] = []
	for input_data in inputs:
		if not (input_data is Dictionary):
			continue
		var item_id: StringName = input_data.get(&"item_id", input_data.get(&"element_id", &""))
		var quantity := int(input_data.get(&"qty", input_data.get(&"quantity", 0)))
		if item_id.is_empty() or quantity <= 0:
			continue
		parts.append("%s x%d" % [_format_item_name(item_id), quantity])
	return ", ".join(parts)


func _create_recipe_entry_card(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.16, 0.96)
	style.border_color = Color(0.29, 0.31, 0.36, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var is_unlocked := bool(entry.get(&"is_unlocked", true))
	var title := Label.new()
	title.text = str(entry.get(&"display_name", "Unknown")) if is_unlocked else str(entry.get(&"locked_name", "???"))
	title.add_theme_font_size_override("font_size", 15)
	content.add_child(title)

	if is_unlocked:
		var recipe_line := Label.new()
		recipe_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		recipe_line.text = "%s -> %s x%d" % [
			_format_recipe_inputs(entry.get(&"inputs", [])),
			_format_item_name(entry.get(&"output_id", &"")),
			int(entry.get(&"output_qty", 1)),
		]
		content.add_child(recipe_line)
	else:
		var locked_label := Label.new()
		locked_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		locked_label.text = str(entry.get(&"locked_hint", "Discover more to identify this recipe."))
		content.add_child(locked_label)

	var station := str(entry.get(&"station", ""))
	if not station.is_empty():
		var station_label := Label.new()
		station_label.text = "Station: %s" % station
		content.add_child(station_label)

	var summary := str(entry.get(&"summary", ""))
	if is_unlocked and not summary.is_empty():
		var summary_label := Label.new()
		summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_label.text = summary
		content.add_child(summary_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)

	var status_label := Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text = "Status: %s" % (str(entry.get(&"status_text", "")) if is_unlocked else "Discovery required")
	footer.add_child(status_label)

	var action_button := Button.new()
	action_button.custom_minimum_size = Vector2(116, 28)
	footer.add_child(action_button)

	var can_execute_from_menu := bool(entry.get(&"can_execute_from_menu", false))
	var recipe_id := StringName(entry.get(&"recipe_id", &""))
	var station_id := StringName(entry.get(&"station_id", &""))

	if is_unlocked and can_execute_from_menu and not recipe_id.is_empty():
		action_button.text = "Craft"
		action_button.disabled = not CraftingManager.can_craft(recipe_id)
		action_button.pressed.connect(_on_recipe_action_pressed.bind(recipe_id))
	else:
		action_button.text = "Use %s" % _get_station_label(station_id) if is_unlocked and not station_id.is_empty() else "Locked"
		action_button.disabled = true

	return panel


func _on_recipe_action_pressed(recipe_id: StringName) -> void:
	if recipe_id.is_empty():
		return
	if not CraftingManager.craft(recipe_id):
		_refresh_build_menu()
		return
	_refresh_build_menu()


func _format_item_name(item_id: StringName) -> String:
	var element_data := ElementDatabase.get_element(item_id)
	if not element_data.is_empty():
		return str(element_data.get(&"display_name", item_id))
	var words := String(item_id).split("_", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)


func _get_station_label(station_id: StringName) -> String:
	if station_id.is_empty():
		return ""
	match station_id:
		&"chem_bench":
			return "Chem Bench"
		&"furnace":
			return "Furnace"
		_:
			return _format_item_name(station_id)


func _get_database_recipe_display_name(recipe_id: StringName, output_id: StringName) -> String:
	match recipe_id:
		&"rust_bolt":
			return "Rust Bolt"
		&"sulfuric_bolt":
			return "Sulfuric Bolt"
		&"distillation_kit":
			return "Distillation Kit"
		_:
			return _format_item_name(output_id)


func _get_database_recipe_summary(recipe_id: StringName) -> String:
	match recipe_id:
		&"rust_bolt":
			return "A low-tier chemistry lead. The pair matters, but the bench conditions decide what you actually get."
		&"sulfuric_bolt":
			return "A volatile chemistry lead. Expect multiple outcomes depending on ratio, heat, and whether the reaction stays under control."
		&"corrosive_slurry":
			return "A buffered sulfur slurry. Stable enough to bottle only when the catalyst and bench conditions are right."
		&"distillation_kit":
			return "Workbench extraction kit required for safe sulfur pickup."
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


func _get_locked_name(recipe: Dictionary) -> String:
	if DiscoveryLog != null and DiscoveryLog.has_method("get_recipe_locked_name"):
		return str(DiscoveryLog.get_recipe_locked_name(recipe))
	return "???"


func _is_pointer_over_build_menu() -> bool:
	return is_instance_valid(_build_menu_panel) and _build_menu_panel.get_global_rect().has_point(get_viewport().get_mouse_position())


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
