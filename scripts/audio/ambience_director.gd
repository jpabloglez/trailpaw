class_name AmbienceDirector
extends Node
## Plays the world's ambience: one looping, non-positional player per [AmbienceLayer], whose
## volume follows the current biome ([code]GameState.current_biome[/code]), the daylight (from
## the [DayNightCycle]'s stars track) and the rain (from the [Weather]), cross-fading over
## [member AmbienceSettings.fade_seconds].
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


func _ready() -> void:
	for layer in settings.layers:
		var player := AudioStreamPlayer.new()
		player.stream = _looping(layer.stream)
		player.bus = settings.bus
		player.volume_db = linear_to_db(SILENT)
		add_child(player)
		_players.append(player)
		_volumes.append(0.0)


func _process(delta: float) -> void:
	advance(delta)


## Moves every layer towards its target volume by [param delta] seconds of fading.
func advance(delta: float) -> void:
	var step := delta / settings.fade_seconds
	var biome := GameState.current_biome
	var light := daylight()
	var rain := weather.rain if weather != null else 0.0
	for i in _players.size():
		var target := settings.layers[i].volume_for(biome, light, rain)
		_volumes[i] = move_toward(_volumes[i], target, step)
		var player := _players[i]
		player.volume_db = linear_to_db(maxf(_volumes[i], SILENT))
		if _volumes[i] > SILENT and not player.playing:
			player.play()
		elif _volumes[i] <= SILENT and player.playing:
			player.stop()


## 0 at night … 1 by day (the inverse of the sky's stars).
func daylight() -> float:
	if day_night == null:
		return 1.0
	var hour := GameState.time_of_day() / 60.0
	return 1.0 - DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour)


## Current volume (linear) of layer [param index].
func volume(index: int) -> float:
	return _volumes[index]


## Player of layer [param index] (tests and tools).
func player(index: int) -> AudioStreamPlayer:
	return _players[index]


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
