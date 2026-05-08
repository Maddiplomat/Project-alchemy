extends AnimationPlayer

const FRAME_COLUMNS := 5
const FRAME_ROWS := 8
const IDLE_FRAME_COLUMN := 0
const WALK_FRAME_COLUMNS := [1, 2, 3, 4]
const WALK_FRAME_DURATION := 0.12
const IDLE_LENGTH := 0.1
const MOVEMENT_THRESHOLD := 5.0
const DEFAULT_STATE := &"idle_south"
const DEFAULT_FACING := &"south"
const ANIMATION_LIBRARY_NAME := &""
const FRAME_TRACK_PATH := NodePath("Visual:frame_coords")
const DIRECTION_BY_ANGLE_SECTOR := [
	&"east",
	&"southeast",
	&"south",
	&"southwest",
	&"west",
	&"northwest",
	&"north",
	&"northeast",
]
const FRAME_LAYOUT := {
	&"south": {"row": 0},
	&"southeast": {"row": 1},
	&"east": {"row": 2},
	&"northeast": {"row": 3},
	&"north": {"row": 4},
	&"northwest": {"row": 5},
	&"west": {"row": 6},
	&"southwest": {"row": 7},
}

@export var character_path: NodePath = NodePath("..")
@export var visual_path: NodePath = NodePath("../Visual")
@export var current_state: StringName = DEFAULT_STATE
@export var current_facing: StringName = DEFAULT_FACING

@onready var _character := get_node(character_path) as CharacterBody2D
@onready var _visual := get_node(visual_path) as Sprite2D


func _ready() -> void:
	if _visual == null or _character == null:
		push_error("PlayerAnimationStateMachine requires a CharacterBody2D parent and Sprite2D visual.")
		set_process(false)
		return

	_visual.hframes = FRAME_COLUMNS
	_visual.vframes = FRAME_ROWS
	set_root_node(NodePath(".."))
	_build_animation_library()
	_transition_to(DEFAULT_STATE)


func _process(_delta: float) -> void:
	var target_state := _get_target_state()
	if target_state != current_state:
		_transition_to(target_state)


func _build_animation_library() -> void:
	if has_animation_library(ANIMATION_LIBRARY_NAME):
		remove_animation_library(ANIMATION_LIBRARY_NAME)

	var animation_library := AnimationLibrary.new()
	for direction: StringName in FRAME_LAYOUT:
		animation_library.add_animation(_get_idle_state(direction), _create_idle_animation(direction))
		animation_library.add_animation(_get_walk_state(direction), _create_walk_animation(direction))

	add_animation_library(ANIMATION_LIBRARY_NAME, animation_library)


func _create_idle_animation(direction: StringName) -> Animation:
	var animation := Animation.new()
	animation.length = IDLE_LENGTH
	animation.loop_mode = Animation.LOOP_LINEAR
	var track := _add_frame_track(animation)
	animation.track_insert_key(track, 0.0, _get_frame_coords(direction, IDLE_FRAME_COLUMN))
	return animation


func _create_walk_animation(direction: StringName) -> Animation:
	var animation := Animation.new()
	animation.length = WALK_FRAME_DURATION * WALK_FRAME_COLUMNS.size()
	animation.loop_mode = Animation.LOOP_LINEAR
	var track := _add_frame_track(animation)

	for frame_index in WALK_FRAME_COLUMNS.size():
		var frame_column: int = WALK_FRAME_COLUMNS[frame_index]
		animation.track_insert_key(track, WALK_FRAME_DURATION * float(frame_index), _get_frame_coords(direction, frame_column))

	return animation


func _add_frame_track(animation: Animation) -> int:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, FRAME_TRACK_PATH)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	return track


func _get_target_state() -> StringName:
	var velocity := _character.velocity
	if velocity.length() <= MOVEMENT_THRESHOLD:
		return _get_idle_state(current_facing)

	current_facing = _get_direction_from_vector(velocity)
	return _get_walk_state(current_facing)


func _get_direction_from_vector(direction: Vector2) -> StringName:
	var sector_count := DIRECTION_BY_ANGLE_SECTOR.size()
	var sector := int(round(direction.angle() / (PI / 4.0)))
	var wrapped_sector := posmod(sector, sector_count)
	return DIRECTION_BY_ANGLE_SECTOR[wrapped_sector]


func _get_frame_coords(direction: StringName, column: int) -> Vector2i:
	var layout: Dictionary = FRAME_LAYOUT[direction]
	return Vector2i(column, layout["row"])


func _get_idle_state(direction: StringName) -> StringName:
	return StringName("idle_%s" % direction)


func _get_walk_state(direction: StringName) -> StringName:
	return StringName("walk_%s" % direction)


func _transition_to(state: StringName) -> void:
	current_state = state
	play(current_state)
