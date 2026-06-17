extends Node2D

const ACID_CRAWLER_SCENE := preload("res://scenes/AcidCrawler.tscn")
const DAY_RESPAWN_SECONDS := 240.0
const NIGHT_RESPAWN_SECONDS := 150.0

@export var spawn_position: Vector2 = Vector2.ZERO

var _active_crawler: Node = null
var _respawn_timer: Timer = null


func _ready() -> void:
	_respawn_timer = Timer.new()
	_respawn_timer.one_shot = true
	_respawn_timer.timeout.connect(_on_respawn_timeout)
	add_child(_respawn_timer)
	if spawn_position == Vector2.ZERO:
		spawn_position = global_position
	_spawn_crawler()


func _spawn_crawler() -> void:
	if ACID_CRAWLER_SCENE == null:
		return
	if _active_crawler != null and is_instance_valid(_active_crawler):
		return

	var crawler := ACID_CRAWLER_SCENE.instantiate()
	add_child(crawler)
	if crawler is Node2D:
		(crawler as Node2D).global_position = spawn_position
	_active_crawler = crawler

	var died_callable := Callable(self, "_on_crawler_died")
	if crawler.has_signal("died") and not crawler.died.is_connected(died_callable):
		crawler.died.connect(died_callable, CONNECT_ONE_SHOT)


func _on_crawler_died(_crawler: CharacterBody2D) -> void:
	_active_crawler = null
	var wait_time := DAY_RESPAWN_SECONDS
	if GameManager.has_method("is_night") and GameManager.is_night():
		wait_time = NIGHT_RESPAWN_SECONDS
	_respawn_timer.wait_time = wait_time
	_respawn_timer.start()


func _on_respawn_timeout() -> void:
	_spawn_crawler()
