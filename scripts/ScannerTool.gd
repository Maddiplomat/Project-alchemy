extends Node2D

@onready var _anim : AnimationPlayer = $ToolAnimationPlayer
@onready var _visuals : Node2D = $ScannerToolVisuals

## Configuration
const SCAN_RADIUS := 80.0
const AUTO_DISMISS := 3.0
const PANEL_OFFSET := Vector2(0, -40)
const PANEL_WIDTH  := 140
const PANEL_HEIGHT := 76
const FALLBACK_COLOUR := Color(0.6, 0.6, 0.6)

const CATEGORY_COLOURS := {
	"organic": Color(0.48, 0.77, 0.46),
	"mineral": Color(0.85, 0.72, 0.45),
	"metal":   Color(0.46, 0.65, 1.0),
	"volatile": Color(1.0, 0.45, 0.45),
	"gas":     Color(0.6, 0.9, 0.9),
	"radioactive": Color(0.7, 1.0, 0.2),
	"catalyst": Color(0.9, 0.5, 1.0)
}

## State
var _space_state : PhysicsDirectSpaceState2D
var _active_panels : Dictionary = {} # Node2D -> Control
var _timers : Dictionary = {}        # Node2D -> float
var _scanning : bool = false
var _canvas : CanvasLayer


func _ready() -> void:
	_space_state = get_world_2d().direct_space_state
	_setup_animations()


func _process(delta: float) -> void:
	if _active_panels.is_empty():
		return

	# Handle auto-dismiss timers
	var to_remove : Array[Node2D] = []
	for pickup in _timers:
		_timers[pickup] -= delta
		if _timers[pickup] <= 0:
			to_remove.append(pickup)

	for pickup in to_remove:
		_remove_panel(pickup)

	# Keep panels pinned to world positions
	for pickup in _active_panels:
		if is_instance_valid(pickup):
			_update_panel_position(_active_panels[pickup], pickup)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("scan"):
		_begin_scan()
	elif event.is_action_released("scan"):
		_end_scan()


func _setup_animations() -> void:
	var anim_lib := AnimationLibrary.new()
	var scan_anim := Animation.new()
	
	# Reset ripple
	scan_anim.track_insert_key(scan_anim.add_track(Animation.TYPE_VALUE), 0.0, 0.0)
	scan_anim.track_set_path(0, "ScannerToolVisuals/ScanRipple:scale")
	scan_anim.track_insert_key(0, 0.0, Vector2(0.1, 0.1))
	scan_anim.track_insert_key(0, 0.4, Vector2(1.2, 1.2)) # ~80px radius at 1.0 scale
	
	scan_anim.track_insert_key(scan_anim.add_track(Animation.TYPE_VALUE), 0.0, 0.0)
	scan_anim.track_set_path(1, "ScannerToolVisuals/ScanRipple:modulate:a")
	scan_anim.track_insert_key(1, 0.0, 0.0)
	scan_anim.track_insert_key(1, 0.05, 0.8)
	scan_anim.track_insert_key(1, 0.4, 0.0)
	
	anim_lib.add_animation("scan", scan_anim)
	_anim.add_animation_library("", anim_lib)


func _begin_scan() -> void:
	if _scanning:
		return
	_scanning = true
	
	var player_pos : Vector2 = (get_parent() as Node2D).global_position
	var query := PhysicsShapeQueryParameters2D.new()
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = SCAN_RADIUS
	query.shape = circle_shape
	query.transform = Transform2D(0.0, player_pos)
	query.collision_mask = 2 # Target ElementPickups specifically
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results := _space_state.intersect_shape(query, 64)
	
	# Play visual ripple
	_anim.play("scan")
	
	for hit in results:
		var collider : Node = hit.get("collider")
		if collider == null:
			continue
		
		# walk up to find the Area2D root of an ElementPickup
		var pickup_node := _find_element_pickup(collider)
		if pickup_node == null or _active_panels.has(pickup_node):
			continue
			
		var element_id : StringName = _resolve_element_id(pickup_node)
		if element_id.is_empty():
			continue
			
		var data := ElementDatabase.get_element(element_id)
		if data.is_empty():
			continue
			
		_spawn_panel(pickup_node, data)
		_flash_element(pickup_node)


func _flash_element(node: Node2D) -> void:
	var tween := create_tween()
	var original := node.modulate
	node.modulate = Color(5, 5, 5, 1) # Bright white flash
	tween.tween_property(node, "modulate", original, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _end_scan() -> void:
	_scanning = false
	_clear_all_panels()


# ── panel helpers ─────────────────────────────────────────────────────────────

func _spawn_panel(pickup: Node2D, data: Dictionary) -> void:
	var panel := _build_panel(data)
	panel.name = "ScannerPanel_" + pickup.name
	# attach to CanvasLayer so it renders on top regardless of z-index
	var canvas := _get_or_create_canvas()
	canvas.add_child(panel)

	# position in screen-space via local_to_map equivalent
	_update_panel_position(panel, pickup)

	_active_panels[pickup] = panel
	_timers[pickup] = AUTO_DISMISS

	# entry animation: fade + slight slide-up
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT)


func _remove_panel(pickup: Node) -> void:
	if not _active_panels.has(pickup):
		return
	var panel : Control = _active_panels[pickup]

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
	tween.tween_callback(panel.queue_free)

	_active_panels.erase(pickup)
	_timers.erase(pickup)


func _clear_all_panels() -> void:
	for pickup in _active_panels.keys():
		var panel : Control = _active_panels[pickup]
		panel.queue_free()
	_active_panels.clear()
	_timers.clear()


func _update_panel_position(panel: Control, pickup: Node2D) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var world_pos : Vector2 = pickup.global_position + PANEL_OFFSET
	var screen_pos : Vector2 = world_pos - camera.get_screen_center_position() \
		+ get_viewport().get_visible_rect().size * 0.5
	panel.position = screen_pos


# ── UI construction ───────────────────────────────────────────────────────────

func _build_panel(data: Dictionary) -> PanelContainer:
	var symbol       : String = str(data.get(&"symbol",       "?"))
	var display_name : String = str(data.get(&"display_name", "Unknown"))
	var category     : String = str(data.get(&"category",     "")).to_lower()
	var weight       : float  = float(data.get(&"weight",     0.0))

	var accent : Color = CATEGORY_COLOURS.get(category, FALLBACK_COLOUR)

	# ── PanelContainer root ──────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# custom StyleBox
	var style := StyleBoxFlat.new()
	style.bg_color            = Color(0.08, 0.09, 0.12, 0.90)
	style.border_color        = accent
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size  = 4
	panel.add_theme_stylebox_override("panel", style)

	# ── VBoxContainer ────────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# header row: coloured badge + symbol + name
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)

	var badge := Label.new()
	badge.text             = symbol
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size  = Vector2(28, 28)
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", accent)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color                  = Color(accent.r, accent.g, accent.b, 0.18)
	badge_style.corner_radius_top_left     = 4
	badge_style.corner_radius_top_right    = 4
	badge_style.corner_radius_bottom_left  = 4
	badge_style.corner_radius_bottom_right = 4
	badge.add_theme_stylebox_override("normal", badge_style)
	header.add_child(badge)

	var name_label := Label.new()
	name_label.text             = display_name
	name_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	# separator line
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(accent.r, accent.g, accent.b, 0.30)
	sep_style.content_margin_top    = 0
	sep_style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# detail row: category + weight
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	vbox.add_child(details)

	var cat_label := Label.new()
	cat_label.text = category.capitalize()
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.85))
	cat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(cat_label)

	var wt_label := Label.new()
	wt_label.text = "%.1f kg" % weight
	wt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wt_label.add_theme_font_size_override("font_size", 10)
	wt_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70, 1.0))
	details.add_child(wt_label)

	return panel


# ── utility ───────────────────────────────────────────────────────────────────

func _find_element_pickup(node: Node) -> Node2D:
	## Walk from collision shape up to its Area2D owner that has ElementPickup script.
	var cur : Node = node
	while cur != null:
		if cur.get_script() != null:
			var s = cur.get_script()
			if s != null and s.resource_path.ends_with("ElementPickup.gd"):
				return cur as Node2D
		cur = cur.get_parent()
	return null


func _resolve_element_id(pickup: Node) -> StringName:
	var eid : StringName = pickup.get(&"element_id") if pickup.has_method("get") else &""
	if eid.is_empty():
		eid = pickup.get_meta(&"element_id", &"")
	return eid


func _get_or_create_canvas() -> CanvasLayer:
	var existing := get_tree().current_scene.get_node_or_null("ScannerCanvas")
	if existing != null:
		return existing as CanvasLayer
	var canvas := CanvasLayer.new()
	canvas.name  = "ScannerCanvas"
	canvas.layer = 128   # above everything
	get_tree().current_scene.add_child(canvas)
	return canvas
