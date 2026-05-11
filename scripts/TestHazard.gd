extends Area2D

@export var damage_amount: int = 8
@export var damage_interval_seconds: float = 0.75
@export var damage_on_entry := true

@onready var _damage_timer := $DamageTimer as Timer

var _tracked_bodies: Array[Node2D] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_damage_timer.wait_time = damage_interval_seconds
	_damage_timer.timeout.connect(_on_damage_timer_timeout)


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return

	var player_body := body as Node2D
	if _tracked_bodies.has(player_body):
		return

	_tracked_bodies.append(player_body)
	if damage_on_entry:
		_apply_damage()
	_update_damage_timer()


func _on_body_exited(body: Node) -> void:
	var tracked_index := _tracked_bodies.find(body)
	if tracked_index == -1:
		return

	_tracked_bodies.remove_at(tracked_index)
	_update_damage_timer()


func _on_damage_timer_timeout() -> void:
	if _tracked_bodies.is_empty():
		_damage_timer.stop()
		return

	_apply_damage()


func _update_damage_timer() -> void:
	if _tracked_bodies.is_empty():
		_damage_timer.stop()
		return

	if not _damage_timer.is_stopped():
		return

	_damage_timer.start()


func _apply_damage() -> void:
	if GameManager.game_state == GameManager.GameState.GAME_OVER:
		_damage_timer.stop()
		return

	GameManager.damage_player(damage_amount)


func _is_player_body(body: Node) -> bool:
	return body is CharacterBody2D and body.name == "Player"
