extends Node2D

const DEFAULT_TILE_SIZE := Vector2i(32, 32)
const COVER_VALID_COLOR := Color(0.38, 0.76, 0.98, 0.26)
const COVER_INVALID_COLOR := Color(0.98, 0.54, 0.22, 0.22)
const SUPPORT_OK_COLOR := Color(0.36, 0.92, 0.48, 0.76)
const SUPPORT_MISSING_COLOR := Color(0.92, 0.28, 0.24, 0.76)

@onready var coverage_markers: Array[Sprite2D] = [
	$Coverage/Coverage00,
	$Coverage/Coverage01,
	$Coverage/Coverage02,
	$Coverage/Coverage03,
	$Coverage/Coverage04,
	$Coverage/Coverage05,
	$Coverage/Coverage06,
	$Coverage/Coverage07,
	$Coverage/Coverage08,
]
@onready var support_markers: Array[Sprite2D] = [
	$Supports/SupportUp,
	$Supports/SupportRight,
	$Supports/SupportDown,
	$Supports/SupportLeft,
]

var _tile_texture: Texture2D = null


func _ready() -> void:
	z_index = 4095
	_tile_texture = _build_preview_tile_texture()
	for marker in coverage_markers:
		marker.texture = _tile_texture
		marker.visible = false
	for marker in support_markers:
		marker.texture = _tile_texture
		marker.scale = Vector2(0.55, 0.55)
		marker.visible = false


func hide_preview() -> void:
	for marker in coverage_markers:
		marker.visible = false
	for marker in support_markers:
		marker.visible = false


func show_preview(ground: TileMapLayer, tile_coords: Vector2i, placement_valid: bool, support_states: Array[bool]) -> void:
	if ground == null:
		hide_preview()
		return

	var coverage_color := COVER_VALID_COLOR if placement_valid else COVER_INVALID_COLOR
	var coverage_index := 0
	for y in range(-1, 2):
		for x in range(-1, 2):
			var coverage_tile := tile_coords + Vector2i(x, y)
			var coverage_marker := coverage_markers[coverage_index]
			coverage_marker.global_position = ground.to_global(ground.map_to_local(coverage_tile))
			coverage_marker.modulate = coverage_color
			coverage_marker.visible = true
			coverage_index += 1

	var support_offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for support_index in range(support_markers.size()):
		var support_tile := tile_coords + support_offsets[support_index]
		var support_marker := support_markers[support_index]
		support_marker.global_position = ground.to_global(ground.map_to_local(support_tile))
		support_marker.modulate = SUPPORT_OK_COLOR if support_states[support_index] else SUPPORT_MISSING_COLOR
		support_marker.visible = true


func _build_preview_tile_texture() -> Texture2D:
	var image := Image.create(DEFAULT_TILE_SIZE.x, DEFAULT_TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	for y in range(DEFAULT_TILE_SIZE.y):
		for x in range(DEFAULT_TILE_SIZE.x):
			var is_border := x <= 1 or y <= 1 or x >= DEFAULT_TILE_SIZE.x - 2 or y >= DEFAULT_TILE_SIZE.y - 2
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if is_border else 0.72))
	return ImageTexture.create_from_image(image)
