class_name SynthSounds
extends RefCounted
## Short sounds synthesised in code where no fitting CC0 recording was found (plan: "if
## something is missing, it is synthesised"): 16-bit mono [AudioStreamWAV]s.

## Sample rate of synthesised sounds.
const RATE: int = 22050

static var _yip: AudioStreamWAV


## A small dog's friendly "yip": two quick chirps gliding down (~0.25 s). Synthesised once
## and shared (it takes a few milliseconds of GDScript).
static func yip() -> AudioStreamWAV:
	if _yip == null:
		_yip = _make_yip()
	return _yip


static func _make_yip() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for chirp in 2:
		var length := int(RATE * 0.09)
		var phase := 0.0
		for i in length:
			var t := float(i) / length
			var frequency := lerpf(950.0, 620.0, t) * (1.0 if chirp == 0 else 0.9)
			phase += TAU * frequency / RATE
			var envelope := sin(PI * t) * (1.0 - t * 0.3)
			var tone := sin(phase) + 0.35 * sin(phase * 2.0) + 0.12 * sin(phase * 3.0)
			samples.append(tone * envelope * 0.55)
		if chirp == 0:
			for i in int(RATE * 0.05):
				samples.append(0.0)
	return to_wav(samples)


## Wraps [param samples] (in [-1, 1]) as a 16-bit mono [AudioStreamWAV] at [constant RATE].
static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
