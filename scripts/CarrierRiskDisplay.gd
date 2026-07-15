class_name CarrierRiskDisplay
extends Node

const GameplayData = preload("res://scripts/GameplayData.gd")
const SFX_DURATION := 0.11
const MAX_WEIGHT_ALPHA := 0.35

var strip: Panel
var warning_label: Label
var hint_label: Label
var vignette: ColorRect
var active_element: StringName = &""
var active_seconds := -1
var weight_alpha := 0.0
var phase := 0.0
var audio_player: AudioStreamPlayer


func configure(risk_strip: Panel, warning: Label, hint: Label, carry_vignette: ColorRect) -> void:
	strip = risk_strip
	warning_label = warning
	hint_label = hint
	vignette = carry_vignette
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.stream = _build_warning_stream()
	set_process(false)


func _process(delta: float) -> void:
	if active_seconds <= 0:
		return
	phase += delta * (9.0 if active_seconds <= 1 else 5.5)
	_update_vignette()


func show_warning(element_id: StringName, seconds_remaining: int) -> void:
	active_element = element_id
	active_seconds = seconds_remaining
	set_process(seconds_remaining > 0)
	strip.visible = true
	var item_name := _get_item_name(element_id)
	warning_label.text = "%s UNSTABLE - %ds" % [item_name.to_upper(), seconds_remaining]
	hint_label.text = "Drop %s from inventory to cancel" % item_name
	_update_vignette()
	if seconds_remaining == 1:
		audio_player.stop()
		audio_player.play()


func clear_warning(element_id: StringName = &"") -> void:
	if not element_id.is_empty() and element_id != active_element:
		return
	active_element = &""
	active_seconds = -1
	phase = 0.0
	set_process(false)
	strip.visible = false
	warning_label.text = "SULFUR UNSTABLE - 3s"
	hint_label.text = "Drop Sulfur from inventory to cancel"
	_update_vignette()


func update_weight(total_weight: float, capacity: float) -> void:
	var ratio := total_weight / capacity if capacity > 0.0 else 0.0
	weight_alpha = 0.0
	if ratio >= 0.9:
		weight_alpha = inverse_lerp(0.9, 1.0, minf(ratio, 1.0)) * MAX_WEIGHT_ALPHA
	_update_vignette()


func _update_vignette() -> void:
	var risk_alpha := 0.0
	if active_seconds > 0:
		var pulse := 0.5 + 0.5 * sin(phase)
		risk_alpha = lerpf(0.12 if active_seconds > 1 else 0.22, 0.24 if active_seconds > 1 else 0.34, pulse)
	vignette.color.a = clampf(weight_alpha + risk_alpha, 0.0, 0.45)


func _get_item_name(item_id: StringName) -> String:
	var data := GameplayData.elements().get_element(item_id)
	return str(data.get(&"display_name", item_id)) if not data.is_empty() else String(item_id).replace("_", " ").capitalize()


func _build_warning_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count := int(sample_rate * SFX_DURATION)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for frame in range(frame_count):
		var t := float(frame) / sample_rate
		var sample := (sin(TAU * 1480.0 * t) * 0.45 + sin(TAU * 2120.0 * t) * 0.18) * (1.0 - float(frame) / frame_count) * 0.8
		var packed := clampi(int(sample * 32767.0), -32768, 32767) & 0xffff
		data[frame * 2] = packed & 0xff
		data[frame * 2 + 1] = packed >> 8 & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
