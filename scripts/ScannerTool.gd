extends Node2D

const SCAN_RADIUS = 80.0
const DISMISS_TIME = 3.0

var active_panels = {} # element_id -> panel

# Custom colors for element categories
const CATEGORY_COLOURS = {
	"Metal": Color(0.7, 0.7, 0.8),
	"Crystal": Color(0.4, 0.8, 0.9),
	"Plant": Color(0.3, 0.8, 0.3),
	"Earth": Color(0.6, 0.4, 0.2),
	"Generic": Color(1, 1, 1)
}

func _input(event):
	if event.is_action_pressed("scan"):
		start_scan()
	elif event.is_action_released("scan"):
		stop_scan()

func start_scan():
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	
	# Create a circle shape for the overlap query
	var circle = CircleShape2D.new()
	circle.radius = SCAN_RADIUS
	query.shape = circle
	query.transform = global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = false # Elements are usually areas or handled via areas
	
	var results = space_state.intersect_shape(query)
	
	for result in results:
		var collider = result.collider
		# Check if the collider is an ElementPickup or has the required data
		if collider.has_method("get_element_id"):
			show_element_info(collider)

func stop_scan():
	for panel in active_panels.values():
		dismiss_panel(panel)
	active_panels.clear()

func show_element_info(element_node):
	var element_id = element_node.get_instance_id()
	if active_panels.has(element_id):
		return
		
	var data = element_node.element_data if "element_data" in element_node else null
	if not data:
		# Fallback to database lookup if data not cached on node
		var id = element_node.element_id if "element_id" in element_node else ""
		data = ElementDatabase.get_element(id)
	
	if not data: return
	
	var canvas = CanvasLayer.new()
	canvas.layer = 128 # High layer to show above UI
	add_child(canvas)
	
	var panel = PanelContainer.new()
	canvas.add_child(panel)
	
	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_width_bottom = 2
	style.border_color = CATEGORY_COLOURS.get(data.category, CATEGORY_COLOURS["Generic"])
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# Title Row (Symbol + Name)
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var symbol_lbl = Label.new()
	symbol_lbl.text = "[%s]" % data.symbol
	symbol_lbl.add_theme_color_override("font_color", style.border_color)
	header.add_child(symbol_lbl)
	
	var name_lbl = Label.new()
	name_lbl.text = data.display_name
	header.add_child(name_lbl)
	
	# Details
	var details = Label.new()
	details.text = "%s | %s kg" % [data.category, data.weight]
	details.add_theme_font_size_override("font_size", 12)
	details.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(details)
	
	# Positioning (Follow element)
	panel.custom_minimum_size = Vector2(120, 0)
	
	active_panels[element_id] = panel
	
	# Animation
	panel.modulate.a = 0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	
	# Update position loop
	_track_element(panel, element_node)
	
	# Auto-dismiss
	get_tree().create_timer(DISMISS_TIME).timeout.connect(func():
		if active_panels.has(element_id) and active_panels[element_id] == panel:
			dismiss_panel(panel)
			active_panels.erase(element_id)
	)

func _track_element(panel, element):
	while is_instance_valid(panel) and is_instance_valid(element):
		var screen_pos = element.get_global_transform_with_canvas().origin
		panel.global_position = screen_pos + Vector2(-60, -60) # Offset above element
		await get_tree().process_frame

func dismiss_panel(panel):
	if not is_instance_valid(panel): return
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.finished.connect(func(): 
		var parent = panel.get_parent()
		if parent is CanvasLayer:
			parent.queue_free()
		else:
			panel.queue_free()
	)
