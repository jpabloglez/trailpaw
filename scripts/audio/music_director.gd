class_name MusicDirector
extends Node
## Plays the music (Phase 20) in spells, as cosy games do: a whole theme, then minutes of
## silence where only the ambience is left. The theme is the current biome's
## ([MusicSettings.theme_for]) in the moment of the day; a biome without one has no music.
## When the wanted theme changes while one plays (a new biome, the night falling), it fades
## out and the new one may start after a short gap. No music in the rain, while the fox rests
## (the clock running fast), or with [code]Settings.music_frequency[/code] "never"; "often"
## shortens the silences. Behind the title screen ([member title_mode]) the title theme plays
## at once and comes back after a short pause.
## [br][br]
## It keeps its own count of the time left in a theme (it does not wait for
## [code]finished[/code]), so [method advance] drives it the same in the game and in tests.
## Budget: a few comparisons per frame.

## What the director is doing.
enum Phase { WAITING, PLAYING, FADING }

## Below this linear volume the theme is inaudible.
const SILENT: float = 0.0001

## The themes and timings.
@export var settings: MusicSettings
## Rain source (optional; dry without it).
@export var weather: Weather

## Behind the title screen: the title theme, at once (set by the [WorldController]).
var title_mode: bool = false:
	set(value):
		title_mode = value
		if value and _phase == Phase.WAITING and _begun:
			_wait = 0.0

var _player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _phase := Phase.WAITING
var _wait: float = 0.0
var _left: float = 0.0
var _volume: float = 0.0
var _current: AudioStream
var _trim: float = 0.0
var _biome: StringName = &""
var _candidate: StringName = &""
var _candidate_for: float = 0.0
var _begun: bool = false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.bus = settings.bus
	_player.volume_db = linear_to_db(SILENT)
	add_child(_player)


func _process(delta: float) -> void:
	advance(delta)


## Moves the music on by [param delta] seconds.
func advance(delta: float) -> void:
	if not _begun:  # on the first frame: the world has set its seed by then
		_begin()
	_settle(delta)
	var wanted := wanted_stream()
	match _phase:
		Phase.WAITING:
			_wait -= delta
			if _wait <= 0.0:
				if wanted != null:
					_start(wanted)
				else:
					_wait = 1.0  # nothing to play here and now: look again in a second
		Phase.PLAYING:
			_left -= delta
			_volume = move_toward(_volume, 1.0, delta / settings.fade_in)
			if wanted != _current:
				_phase = Phase.FADING
			elif _left <= 0.0:
				_stop(_pause())
		Phase.FADING:
			_volume = move_toward(_volume, 0.0, delta / settings.fade_out)
			_left -= delta
			if _volume <= 0.0 or _left <= 0.0:
				_stop(_rng.randf_range(settings.change_gap.x, settings.change_gap.y))
	_player.volume_db = linear_to_db(maxf(_volume, SILENT)) + _trim


## The theme that should be playing now (null: silence).
func wanted_stream() -> AudioStream:
	if Settings.music_frequency == &"never" or settings == null:
		return null
	var biome := settings.title_biome if title_mode else _biome
	var theme := settings.theme_for(biome)
	if theme == null:
		return null
	if title_mode:
		return theme.stream_for(settings.title_moment)
	if weather != null and weather.rain_here > settings.rain_threshold:
		return null
	if GameState.clock_scale > 1.0:  # resting: the clock runs fast
		return null
	return theme.stream_for(settings.moment_of(GameState.time_of_day() / 60.0))


## What it is doing ([enum Phase]).
func phase() -> Phase:
	return _phase


## The theme playing or fading (null when silent).
func current() -> AudioStream:
	return _current


## Its volume now (linear, 0…1, before the theme's trim and the bus).
func volume() -> float:
	return _volume


## Seconds of silence left before it may play.
func waiting() -> float:
	return _wait


## The player (tests).
func player() -> AudioStreamPlayer:
	return _player


func _begin() -> void:
	_begun = true
	_rng.seed = hash([GameState.world_seed, &"music"])
	_biome = GameState.current_biome
	_candidate = _biome
	_wait = 0.0 if title_mode else _rng.randf_range(settings.first_spell.x, settings.first_spell.y)


# Follows the biome once the fox has stayed in it for [member MusicSettings.settle_seconds].
func _settle(delta: float) -> void:
	var now := GameState.current_biome
	if now != _candidate:
		_candidate = now
		_candidate_for = 0.0
		return
	_candidate_for += delta
	if _candidate_for >= settings.settle_seconds or _biome == &"":
		_biome = _candidate


func _start(stream: AudioStream) -> void:
	_current = stream
	_left = stream.get_length()
	_volume = 0.0
	var theme := settings.theme_for(settings.title_biome if title_mode else _biome)
	_trim = theme.volume_db if theme != null else 0.0
	_phase = Phase.PLAYING
	_player.stream = stream
	_player.volume_db = linear_to_db(SILENT) + _trim
	_player.play()


func _stop(silence: float) -> void:
	_player.stop()
	_current = null
	_volume = 0.0
	_phase = Phase.WAITING
	_wait = silence


# The silence after a whole theme.
func _pause() -> float:
	if title_mode:
		return settings.title_pause
	var pause := _rng.randf_range(settings.pauses.x, settings.pauses.y)
	return pause * (settings.often_factor if Settings.music_frequency == &"often" else 1.0)
