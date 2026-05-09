extends Area2D

signal picked_up(item_data: Dictionary, quantity: int)

static var _shape_logged := false

@export var element_id: StringName = &""
@export var pickup_quantity := 1

@onready var prompt_label := $PromptLabel as Label
@onready var collision_shape := $CollisionShape2D as CollisionShape2D

var _player_in_range: CharacterBody2D = null


func _ready() -> void:
	prompt_label.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var inventory_callable := Callable(InventoryManager, "receive_world_pickup")
	if not picked_up.is_connected(inventory_callable):
		picked_up.connect(inventory_callable)

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

	if not InventoryManager.can_add_item(item_data, pickup_quantity):
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

	var item_data := ElementDatabase.get_element(resolved_element_id)
	if item_data.is_empty():
		return {}

	item_data[&"category"] = InventoryManager.InventoryItemCategory.ELEMENT
	item_data[&"risk_level"] = _to_inventory_risk_level(str(item_data.get(&"carrier_risk", "none")))
	return item_data


func _to_inventory_risk_level(risk_level_name: String) -> int:
	match risk_level_name.to_lower():
		"low":
			return InventoryManager.InventoryRiskLevel.LOW
		"medium":
			return InventoryManager.InventoryRiskLevel.MEDIUM
		"high":
			return InventoryManager.InventoryRiskLevel.HIGH
		"extreme":
			return InventoryManager.InventoryRiskLevel.EXTREME
		_:
			return InventoryManager.InventoryRiskLevel.NONE


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
