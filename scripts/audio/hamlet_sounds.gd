class_name HamletSounds
extends Node
## The sounds of the hamlets: hens about the yard (a positional loop at the well, by day), the
## rooster at dawn ([member HamletSoundSettings.rooster_hour], once a day per hamlet), a sheep, cow
## or pig calling from the pen now and then, and a villager's claps when it shoos the fox
## ([code]EventBus.fox_shooed[/code]). All positional on the SFX bus, so they fade with distance.
## [br][br]
## Budget: a couple of players per built hamlet; a time check per hamlet a few times a second.

## What plays, when and how loud.
@export var settings: HamletSoundSettings
## The hamlets.
@export var director: HamletDirector

## Rooster crows and pen calls so far (tests and tools).
var crows: int = 0
var calls: int = 0

var _yards: Dictionary[Vector2i, AudioStreamPlayer3D] = {}
var _voices: Dictionary[Vector2i, AudioStreamPlayer3D] = {}  # rooster and pen calls
var _pens: Dictionary[Vector2i, Vector3] = {}  # local to the hamlet's root (INF: none)
var _next_call: Dictionary[Vector2i, float] = {}
var _last_hour: float = -1.0
var _shoo: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _since: float = 0.0


func _ready() -> void:
	_rng.seed = 0x50D
	_shoo = _player(settings.shoo, settings.shoo_db, settings.call_reach)
	add_child(_shoo)
	EventBus.fox_shooed.connect(on_shooed)
	if director != null:
		director.hamlet_built.connect(add_hamlet)
		director.hamlet_freed.connect(remove_hamlet)


func _process(delta: float) -> void:
	_since += delta
	if _since >= 0.25:
		update(_since)
		_since = 0.0


## Gives the hamlet of [param layout] its yard and its voices (under [param root]).
func add_hamlet(layout: HamletLayout, root: Node3D) -> void:
	var yard := _player(_looping(settings.yard), settings.yard_db, settings.yard_reach)
	yard.name = "YardSound"
	root.add_child(yard)
	var voice := _player(null, settings.call_db, settings.call_reach)
	voice.name = "Voices"
	root.add_child(voice)
	_yards[layout.cell] = yard
	_voices[layout.cell] = voice
	_pens[layout.cell] = layout.pen - layout.centre if layout.pen != Vector3.INF else Vector3.INF
	_next_call[layout.cell] = _rng.randf_range(settings.call_seconds.x, settings.call_seconds.y)


## Forgets the hamlet of [param cell] (its players go with its root).
func remove_hamlet(cell: Vector2i) -> void:
	_yards.erase(cell)
	_voices.erase(cell)
	_pens.erase(cell)
	_next_call.erase(cell)


## Starts and stops the yard with the day, crows at dawn and calls from the pens.
## [param elapsed] seconds since the last call.
func update(elapsed: float) -> void:
	var hour := GameState.time_of_day() / 60.0
	var daytime := is_daytime(hour)
	var crow := _last_hour >= 0.0 and crosses(_last_hour, hour, settings.rooster_hour)
	_last_hour = hour
	for cell: Vector2i in _yards:
		var yard := _yards[cell]
		if not is_instance_valid(yard):
			continue
		if daytime and not yard.playing and yard.is_inside_tree():
			yard.play(_rng.randf() * 10.0)  # each hamlet's hens at their own point of the loop
		elif not daytime and yard.playing:
			yard.stop()
		var voice := _voices[cell]
		if crow:
			_say(voice, settings.rooster, settings.rooster_db, Vector3(3.0, 2.5, 3.0))
			crows += 1
			continue
		if not daytime or _pens[cell] == Vector3.INF or settings.pen_calls.is_empty():
			continue
		_next_call[cell] -= elapsed
		if _next_call[cell] <= 0.0:
			_next_call[cell] = _rng.randf_range(settings.call_seconds.x, settings.call_seconds.y)
			var call := settings.pen_calls[_rng.randi() % settings.pen_calls.size()]
			_say(voice, call, settings.call_db, _pens[cell])
			calls += 1


## Claps where a villager shoos the fox (global [param from]).
func on_shooed(from: Vector3) -> void:
	if not _shoo.is_inside_tree():
		return
	_shoo.global_position = from + Vector3.UP * 1.2
	_shoo.pitch_scale = _rng.randf_range(0.95, 1.05)
	_shoo.play()


## Whether the yard is alive at [param hour] (hens out).
func is_daytime(hour: float) -> bool:
	return hour >= settings.day.x and hour < settings.day.y


## Whether the clock went past [param mark] between [param before] and [param now] (hours,
## wrapping at midnight; a jump of more than half a day counts as not crossing).
static func crosses(before: float, now: float, mark: float) -> bool:
	var span := fposmod(now - before, 24.0)
	if span <= 0.0 or span > 12.0:
		return false
	return fposmod(mark - before, 24.0) <= span and fposmod(mark - before, 24.0) > 0.0


## The yard player of the hamlet of [param cell] (null when not built).
func yard_of(cell: Vector2i) -> AudioStreamPlayer3D:
	return _yards.get(cell)


## The player that claps for a shoo.
func shoo_player() -> AudioStreamPlayer3D:
	return _shoo


func _say(voice: AudioStreamPlayer3D, stream: AudioStream, db: float, at: Vector3) -> void:
	if not is_instance_valid(voice) or not voice.is_inside_tree():
		return
	voice.stream = stream
	voice.volume_db = db
	voice.position = at
	voice.pitch_scale = _rng.randf_range(0.92, 1.08)
	voice.play()


func _player(stream: AudioStream, db: float, reach: Vector2) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = db
	player.unit_size = reach.x
	player.max_distance = reach.y
	return player


# A copy of [param stream] that loops (imported clips do not by default).
static func _looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		return wav
	return stream
