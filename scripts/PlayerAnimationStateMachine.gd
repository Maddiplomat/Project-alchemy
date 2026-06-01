extends Node

const IDLE_FRAME_COLUMN := 0
const WALK_FRAME_COLUMNS := [1, 2, 3, 4]
const WALK_FRAME_COLUMNS_BY_DIRECTION := {
	&"south": [1, 0, 1, 0],
}
const WALK_FRAMES_PER_SECOND := 8.0
const MOVEMENT_THRESHOLD := 5.0
const DEFAULT_STATE := &"idle_south"
const DEFAULT_FACING := &"south"
const FRAME_DIRECTORY := "res://assets/player/frames_small"
const FRAME_LAYOUT := {
	&"south": {"row": 0},
	&"north": {"row": 1},
	&"west": {"row": 2},
	&"east": {"row": 3},
}

@export var character_path: NodePath = NodePath("..")
@export var visual_path: NodePath = NodePath("../Visual")
@export var current_state: StringName = DEFAULT_STATE
@export var current_facing: StringName = DEFAULT_FACING

@onready var _character := get_node(character_path) as CharacterBody2D
@onready var _visual := get_node(visual_path) as AnimatedSprite2D


func _ready() -> void:
	if _visual == null or _character == null:
		push_error("PlayerAnimationStateMachine requires a CharacterBody2D parent and AnimatedSprite2D visual.")
		set_process(false)
		return

	_build_sprite_frames()
	_transition_to(DEFAULT_STATE)


func _process(_delta: float) -> void:
	var target_state := _get_target_state()
	if target_state != current_state:
		_transition_to(target_state)


func _build_sprite_frames() -> void:
	var atlas := _visual.sprite_frames
	if atlas == null:
		atlas = SpriteFrames.new()
	else:
		for animation_name in atlas.get_animation_names():
			atlas.remove_animation(animation_name)

	for direction: StringName in FRAME_LAYOUT:
		_add_idle_animation(atlas, direction)
		_add_walk_animation(atlas, direction)

	_visual.sprite_frames = atlas


func _add_idle_animation(frames: SpriteFrames, direction: StringName) -> void:
	var animation_name := String(_get_idle_state(direction))
	frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, true)
	frames.set_animation_speed(animation_name, 1.0)
	frames.add_frame(animation_name, _load_frame_texture(direction, IDLE_FRAME_COLUMN))


func _add_walk_animation(frames: SpriteFrames, direction: StringName) -> void:
	var animation_name := String(_get_walk_state(direction))
	frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, true)
	frames.set_animation_speed(animation_name, WALK_FRAMES_PER_SECOND)
	var frame_columns: Array = WALK_FRAME_COLUMNS_BY_DIRECTION.get(direction, WALK_FRAME_COLUMNS)
	for frame_column in frame_columns:
		frames.add_frame(animation_name, _load_frame_texture(direction, frame_column))


func _load_frame_texture(direction: StringName, column: int) -> Texture2D:
	var texture_path := "%s/%s_%d.png" % [FRAME_DIRECTORY, String(direction), column]
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_error("Missing player frame texture: %s" % texture_path)
	return texture


func _get_target_state() -> StringName:
	var velocity := _character.velocity
	if velocity.length() <= MOVEMENT_THRESHOLD:
		return _get_idle_state(current_facing)

	current_facing = _get_direction_from_vector(velocity)
	return _get_walk_state(current_facing)


func _get_direction_from_vector(direction: Vector2) -> StringName:
	if absf(direction.x) > absf(direction.y):
		return &"east" if direction.x > 0.0 else &"west"
	return &"south" if direction.y > 0.0 else &"north"


func _get_idle_state(direction: StringName) -> StringName:
	return StringName("idle_%s" % direction)


func _get_walk_state(direction: StringName) -> StringName:
	return StringName("walk_%s" % direction)


func _transition_to(state: StringName) -> void:
	current_state = state
	if _visual.animation != String(state):
		_visual.play(String(state))
