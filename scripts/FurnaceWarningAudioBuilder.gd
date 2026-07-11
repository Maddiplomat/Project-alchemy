class_name FurnaceWarningAudioBuilder
extends RefCounted


static func build(cached_stream: AudioStreamWAV = null) -> AudioStreamWAV:
	if cached_stream != null:
		return cached_stream

	var mix_rate := 22050
	var duration_seconds := 0.12
	var sample_count := int(float(mix_rate) * duration_seconds)
	var pcm_bytes := PackedByteArray()
	pcm_bytes.resize(sample_count * 2)
	var frequency := 1240.0

	for sample_index in range(sample_count):
		var envelope := 1.0 - (float(sample_index) / float(sample_count))
		var sample_value := sin(TAU * frequency * (float(sample_index) / float(mix_rate))) * envelope
		var pcm_value := int(clampi(int(round(sample_value * 12000.0)), -32768, 32767))
		var encoded_value := pcm_value if pcm_value >= 0 else 65536 + pcm_value
		pcm_bytes[sample_index * 2] = encoded_value & 0xff
		pcm_bytes[sample_index * 2 + 1] = (encoded_value >> 8) & 0xff

	var stream := AudioStreamWAV.new()
	stream.mix_rate = mix_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = pcm_bytes
	return stream
