class_name EnemyAI
extends Node

## EnemyAI Base Class
## Defines abstract methods for core enemy behaviors.

enum State {
	IDLE,
	PATROL,
	ALERT,
	ATTACK,
	DEAD
}

var current_state: State = State.IDLE

func _process(delta: float) -> void:
	match current_state:
		State.PATROL:
			patrol()
		State.ALERT:
			alert()
		State.ATTACK:
			attack()
		State.DEAD:
			pass

# Virtual methods for subclasses to override.
# The base implementation is intentionally silent so a missing override does not
# flood the log every frame and hide real runtime errors.
func patrol() -> void:
	pass

func alert() -> void:
	pass

func attack() -> void:
	pass

func die() -> void:
	current_state = State.DEAD
