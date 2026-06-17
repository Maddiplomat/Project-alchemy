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

# Virtual methods to be overridden by subclasses
func patrol() -> void:
	push_warning("patrol() not implemented in ", get_class())

func alert() -> void:
	push_warning("alert() not implemented in ", get_class())

func attack() -> void:
	push_warning("attack() not implemented in ", get_class())

func die() -> void:
	current_state = State.DEAD
	push_warning("die() not implemented in ", get_class())
