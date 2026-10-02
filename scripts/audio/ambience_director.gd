class_name AmbienceDirector
extends Node
## Plays the world's ambience: one looping, non-positional player per [AmbienceLayer], whose
## volume follows the current biome ([code]GameState.current_biome[/code]), the daylight (from
## the [DayNightCycle]'s stars track) and the rain (from the [Weather]), cross-fading over
## [member AmbienceSettings.fade_seconds]. Intermittent layers (the birdsong, see
## [method AmbienceLayer.is_intermittent]) are gated on and off in spells of random length,
## seeded from the world seed, and each spell starts at a random point of its loop.
## [br][br]
## Budget: per frame, one volume target and one [code]move_toward[/code] per layer (6 layers).

## Below this linear volume a layer is paused.
const SILENT: float = 0.001

## The mix.
@export var settings: AmbienceSettings
## Daylight source (optional; full day without it).
@export var day_night: DayNightCycle
## Rain source (optional; dry without it).
@export var weather: Weather

var _players: Array[AudioStreamPlayer] = []
var _volumes := PackedFloat32Array()
var _open := PackedByteArray()
var _gate_left := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash([GameState.world_seed, &"ambience"])
	for layer in settings.layers:
		var player := AudioStreamPlayer.new()
		player.stream = _looping(layer.stream)
		player.bus = settings.bus
		player.volume_db = linear_to_db(SILENT)
		add_child(player)
		_players.append(player)
		_volumes.append(0.0)
		# Intermittent layers start silent; the first spell comes within the shortest pause.
		_open.append(0)
		_gate_left.append(_rng.randf_range(0.0, layer.pauses.x))


func _process(delta: float) -> void:
	advance(delta)


## Moves every layer towards its target volume by [param delta] seconds of fading.
func advance(delta: float) -> void:
	var step := delta / settings.fade_seconds
	var biome := GameState.current_biome
	var light := daylight()
	var rain := weather.rain if weather != null else 0.0
	for i in _players.size():
		var layer := settings.layers[i]
		var target := layer.volume_for(biome, light, rain)
		if layer.is_intermittent():
			target *= _advance_gate(i, layer, delta)
		_volumes[i] = move_toward(_volumes[i], target, step)
		var player := _players[i]
		player.volume_db = linear_to_db(maxf(_volumes[i], SILENT))
		if _volumes[i] > SILENT and not player.playing:
			player.play(_rng.randf() * player.stream.get_length())
		elif _volumes[i] <= SILENT and player.playing:
			player.stop()


## 0 at night … 1 by day (the inverse of the sky's stars).
func daylight() -> float:
	if day_night == null:
		return 1.0
	var hour := GameState.time_of_day() / 60.0
	return 1.0 - DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour)


## Whether intermittent layer [param index] is in a spell (always true for continuous layers).
func is_open(index: int) -> bool:
	return not settings.layers[index].is_intermittent() or _open[index] == 1


## Current volume (linear) of layer [param index].
func volume(index: int) -> float:
	return _volumes[index]


## Player of layer [param index] (tests and tools).
func player(index: int) -> AudioStreamPlayer:
	return _players[index]


# 1 while layer [param index] is in a spell, 0 during a pause; flips when its time runs out.
func _advance_gate(index: int, layer: AmbienceLayer, delta: float) -> float:
	_gate_left[index] -= delta
	if _gate_left[index] <= 0.0:
		_open[index] = 1 - _open[index]
		var span := layer.spells if _open[index] == 1 else layer.pauses
		_gate_left[index] += _rng.randf_range(span.x, span.y)
	return float(_open[index])


## A copy of [param stream] that loops (imported clips do not loop by default).
static func _looping(stream: AudioStream) -> AudioStream:
	var copy := stream.duplicate() as AudioStream
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	elif copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return copy
