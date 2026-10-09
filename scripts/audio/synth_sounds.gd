class_name SynthSounds
extends RefCounted
## Short sounds synthesised in code where no fitting CC0 recording was found (plan: "if
## something is missing, it is synthesised"): 16-bit mono [AudioStreamWAV]s.

## Sample rate of synthesised sounds.
const RATE: int = 22050

static var _yip: AudioStreamWAV
static var _plop: AudioStreamWAV
static var _chime: AudioStreamWAV


## A small dog's friendly "yip": two quick chirps gliding down (~0.25 s). Synthesised once
## and shared (it takes a few milliseconds of GDScript).
static func yip() -> AudioStreamWAV:
	if _yip == null:
		_yip = _make_yip()
	return _yip


## A small "plop" of something dropping into water (a frog diving): a bubble's resonance
## rising quickly and dying away (~0.15 s). Synthesised once and shared.
static func plop() -> AudioStreamWAV:
	if _plop == null:
		_plop = _make_plop()
	return _plop


## A soft two-note chime (a new animal in the journal): bell-like tones, a fifth apart, that
## ring out (~0.9 s). Synthesised once and shared.
static func chime() -> AudioStreamWAV:
	if _chime == null:
		_chime = _make_chime()
	return _chime


static func _make_chime() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(RATE * 0.9))
	samples.fill(0.0)
	for note: Array in [[659.25, 0.0], [987.77, 0.12]]:  # E5, then B5
		var start := int(RATE * float(note[1]))
		for i in range(start, samples.size()):
			var t := float(i - start) / RATE
			var envelope := exp(-t * 5.0) * minf(1.0, t * 300.0)
			var tone := sin(TAU * float(note[0]) * t) + 0.25 * sin(TAU * float(note[0]) * 2.0 * t)
			samples[i] += tone * envelope * 0.32
	return to_wav(samples)


static func _make_plop() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var length := int(RATE * 0.15)
	var phase := 0.0
	var noise := RandomNumberGenerator.new()
	noise.seed = 7
	for i in length:
		var t := float(i) / RATE
		var frequency := 320.0 + 900.0 * (1.0 - exp(-t * 28.0))
		phase += TAU * frequency / RATE
		var envelope := exp(-t * 22.0) * minf(1.0, t * 900.0)
		var splash := noise.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.25
		samples.append((sin(phase) * envelope + splash) * 0.6)
	return to_wav(samples)


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
