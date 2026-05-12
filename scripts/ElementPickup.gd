extends Area2D

signal picked_up(item_data: Dictionary, quantity: int)

static var _shape_logged := false

@export var element_id: StringName = &""
@export var pickup_quantity := 1

@onready var prompt_label := $PromptLabel as Label
@onready var collision_shape := $CollisionShape2D as CollisionShape2D
@onready var anim_player := $AnimationPlayer as AnimationPlayer
@onready var sprite := $Sprite2D as Sprite2D

var _player_in_range: CharacterBody2D = null


func _ready() -> void:
	prompt_label.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_setup_animations()
	_play_idle_animation()

	_log_shape_size_once()


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range == null or not prompt_label.visible:
		return

	if event.is_action_pressed("interact"):
		_attempt_pickup()


func _on_body_entered(body: Node) -> void:
	if not body is CharacterBody2D:
		return

	_player_in_range = body
	prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if body != _player_in_range:
		return

	_player_in_range = null
	prompt_label.visible = false


func _attempt_pickup() -> void:
	var item_data := _get_pickup_item_data()
	if item_data.is_empty():
		return

	if not InventoryManager.add_element(item_data.id, pickup_quantity, 1.0):
		return

	picked_up.emit(item_data, pickup_quantity)
	prompt_label.visible = false
	queue_free()


func _get_pickup_item_data() -> Dictionary:
	var resolved_element_id := element_id
	if resolved_element_id.is_empty():
		resolved_element_id = get_meta(&"element_id", &"")

	if resolved_element_id.is_empty():
		return {}

	return ElementDatabase.get_element(resolved_element_id)


func _log_shape_size_once() -> void:
	if _shape_logged:
		return

	var rectangle_shape := collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		return

	var runtime := get_tree().root.get_node_or_null("MCPRuntime")
	if runtime == null or not runtime.has_method("push_runtime_log"):
		return

	runtime.push_runtime_log("info", "ElementPickup collision size=%s extents=%s" % [rectangle_shape.size, rectangle_shape.size * 0.5])
	_shape_logged = true


func _setup_animations() -> void:
	var lib := AnimationLibrary.new()
	
	# Wood: gentle sway
	var anim_wood := Animation.new()
	anim_wood.length = 1.5
	anim_wood.loop_mode = Animation.LOOP_LINEAR
	var track_wood := anim_wood.add_track(Animation.TYPE_VALUE)
	anim_wood.track_set_path(track_wood, "Sprite2D:rotation")
	anim_wood.track_insert_key(track_wood, 0.0, 0.0)
	anim_wood.track_insert_key(track_wood, 0.375, deg_to_rad(2.0))
	anim_wood.track_insert_key(track_wood, 0.75, 0.0)
	anim_wood.track_insert_key(track_wood, 1.125, deg_to_rad(-2.0))
	anim_wood.track_insert_key(track_wood, 1.5, 0.0)
	lib.add_animation("idle_wood", anim_wood)
	
	# Stone: none
	var anim_stone := Animation.new()
	anim_stone.length = 1.5
	anim_stone.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle_stone", anim_stone)
	
	# Iron: glint pulse
	var anim_iron := Animation.new()
	anim_iron.length = 1.5
	anim_iron.loop_mode = Animation.LOOP_LINEAR
	var track_iron := anim_iron.add_track(Animation.TYPE_VALUE)
	anim_iron.track_set_path(track_iron, "Sprite2D:modulate")
	anim_iron.track_insert_key(track_iron, 0.0, Color(1, 1, 1, 1.0))
	anim_iron.track_insert_key(track_iron, 0.75, Color(1, 1, 1, 0.85))
	anim_iron.track_insert_key(track_iron, 1.5, Color(1, 1, 1, 1.0))
	lib.add_animation("idle_iron", anim_iron)
	
	anim_player.add_animation_library("", lib)


func _play_idle_animation() -> void:
	var resolved_element_id := element_id
	if resolved_element_id.is_empty():
		resolved_element_id = get_meta(&"element_id", &"")
		
	var anim_name := "idle_" + str(resolved_element_id)
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)


func get_element_id() -> StringName:
	if not element_id.is_empty():
		return element_id
	return get_meta(&"element_id", &"")
