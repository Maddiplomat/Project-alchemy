extends Node2D

const WARNING_ID := &"rain"
const MIN_SQUALL_INTERVAL_SECONDS := 300.0
const MAX_SQUALL_INTERVAL_SECONDS := 480.0
const WARNING_WINDOW_SECONDS := 5.0
const SQUALL_DURATION_SECONDS := 30.0
const NORMAL_CANVAS_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SQUALL_CANVAS_COLOR := Color(0.74, 0.80, 0.88, 1.0)
const RAIN_PARTICLE_RATE := 60.0
const RAIN_PARTICLE_LIFETIME := 1.0

var _rng := RandomNumberGenerator.new()
var _squall_timer: Timer = null
var _warning_timer: SceneTreeTimer = null
var _squall_end_timer: SceneTreeTimer = null
var _canvas_tween: Tween = null
var _rain_particles: GPUParticles2D = null
var _thunder_audio_player: AudioStreamPlayer2D = null
var _squall_active := false


func _ready() -> void:
	_rng.randomize()
	_squall_timer = Timer.new()
	_squall_timer.one_shot = true
	_squall_timer.timeout.connect(_begin_warning_window)
	add_child(_squall_timer)

	_rain_particles = GPUParticles2D.new()
	_rain_particles.name = "RainParticles"
	_rain_particles.local_coords = false
	_rain_particles.emitting = false
	_rain_particles.z_index = 20
	add_child(_rain_particles)
	_configure_rain_particles()

	_thunder_audio_player = AudioStreamPlayer2D.new()
	_thunder_audio_player.name = "ThunderAudioPlayer"
	_thunder_audio_player.stream = _build_thunder_stream()
	add_child(_thunder_audio_player)

	set_process(false)
	_schedule_next_squall()


func _process(_delta: float) -> void:
	if not _squall_active or _rain_particles == null:
		return
	var player := _get_player()
	if player == null:
		return
	_rain_particles.global_position = player.global_position + Vector2(0.0, -220.0)


func _schedule_next_squall() -> void:
	if _squall_timer == null:
		return
	_squall_timer.start(_rng.randf_range(MIN_SQUALL_INTERVAL_SECONDS, MAX_SQUALL_INTERVAL_SECONDS))


func _begin_warning_window() -> void:
	_play_thunder_sfx()
	_tween_canvas_to(SQUALL_CANVAS_COLOR, WARNING_WINDOW_SECONDS)
	_warning_timer = get_tree().create_timer(WARNING_WINDOW_SECONDS)
	_warning_timer.timeout.connect(_start_squall, CONNECT_ONE_SHOT)


func _start_squall() -> void:
	_squall_active = true
	GameManager.set_environmental_warning(WARNING_ID, true)
	if _rain_particles != null:
		var player := _get_player()
		if player != null:
			_rain_particles.global_position = player.global_position + Vector2(0.0, -220.0)
		_rain_particles.restart()
		_rain_particles.emitting = true
	set_process(true)
	_squall_end_timer = get_tree().create_timer(SQUALL_DURATION_SECONDS)
	_squall_end_timer.timeout.connect(_end_squall, CONNECT_ONE_SHOT)


func _end_squall() -> void:
	_squall_active = false
	GameManager.set_environmental_warning(WARNING_ID, false)
	if _rain_particles != null:
		_rain_particles.emitting = false
	set_process(false)
	_tween_canvas_to(NORMAL_CANVAS_COLOR, 2.0)
	_schedule_next_squall()


func _tween_canvas_to(target_color: Color, duration: float) -> void:
	var canvas_modulate := _get_canvas_modulate()
	if canvas_modulate == null:
		return
	if _canvas_tween != null:
		_canvas_tween.kill()
	_canvas_tween = create_tween()
	_canvas_tween.set_trans(Tween.TRANS_SINE)
	_canvas_tween.set_ease(Tween.EASE_IN_OUT)
	_canvas_tween.tween_property(canvas_modulate, "color", target_color, duration)


func _get_canvas_modulate() -> CanvasModulate:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("CanvasModulate") as CanvasModulate


func _get_player() -> Node2D:
	return GameManager.get_player()


func _configure_rain_particles() -> void:
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(420.0, 12.0, 0.0)
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 4.0
	process_material.initial_velocity_min = 360.0
	process_material.initial_velocity_max = 440.0
	process_material.gravity = Vector3(0.0, 60.0, 0.0)
	process_material.scale_min = 0.55
	process_material.scale_max = 0.8
	process_material.color = Color(0.78, 0.88, 1.0, 0.78)
	process_material.color_ramp = _build_rain_gradient()
	_rain_particles.process_material = process_material
	_rain_particles.texture = _build_rain_texture()
	var particle_scale := 1.0
	if MobilePerformance != null and MobilePerformance.has_method("get_particle_amount_scale"):
		particle_scale = float(MobilePerformance.get_particle_amount_scale())
	_rain_particles.amount = maxi(24, int(ceili(RAIN_PARTICLE_RATE * RAIN_PARTICLE_LIFETIME * particle_scale)))
	_rain_particles.lifetime = RAIN_PARTICLE_LIFETIME
	_rain_particles.one_shot = false
	_rain_particles.explosiveness = 0.0
	_rain_particles.amount_ratio = 1.0
	_rain_particles.visibility_rect = Rect2(Vector2(-460.0, -260.0), Vector2(920.0, 540.0))


func _build_rain_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.84, 0.92, 1.0, 0.0))
	gradient.add_point(0.15, Color(0.78, 0.88, 1.0, 0.82))
	gradient.add_point(1.0, Color(0.72, 0.84, 1.0, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_rain_texture() -> Texture2D:
	var image := Image.create(2, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(12):
		var alpha := 0.25 + (0.75 * (1.0 - absf((float(y) - 5.5) / 5.5)))
		image.set_pixel(0, y, Color(0.86, 0.93, 1.0, alpha))
		image.set_pixel(1, y, Color(0.76, 0.87, 1.0, alpha * 0.82))
	return ImageTexture.create_from_image(image)


func _play_thunder_sfx() -> void:
	if _thunder_audio_player == null or _thunder_audio_player.stream == null:
		return
	_thunder_audio_player.stop()
	_thunder_audio_player.play()


func _build_thunder_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count := int(sample_rate * 1.6)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for frame in range(frame_count):
		var t := float(frame) / float(sample_rate)
		var envelope := exp(-t * 2.4)
		var rumble := sin(TAU * 42.0 * t) * 0.40 + sin(TAU * 78.0 * t) * 0.22
		var crack := sin(TAU * 860.0 * t) * 0.10 if t < 0.12 else 0.0
		var sample := (rumble + crack) * envelope
		var sample_value := int(clampi(int(sample * 32767.0), -32768, 32767))
		var packed_value := sample_value & 0xffff
		data[frame * 2] = packed_value & 0xff
		data[frame * 2 + 1] = (packed_value >> 8) & 0xff

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func is_raining() -> bool:
	return _squall_active
