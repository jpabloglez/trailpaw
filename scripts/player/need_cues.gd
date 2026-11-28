class_name NeedCues
extends Node3D
## Body language and sounds of the active need cues ([method NeedEffects.cues], ADR-012), so
## the player can tell what the animal lacks without looking at the HUD:
## [code]&"pant"[/code] (thirst or heat) breathes quickly — the chest rises and a breathy loop
## plays; [code]&"growl"[/code] (hunger) rumbles now and then; [code]&"shiver"[/code] (cold)
## rolls the body in small, quick shakes. [code]&"tired"[/code] is the tired idle
## ([AnimationController]). Each cue fades in and out; the motion is applied to the species
## model under [member model_root] on top of its spawn scale and yaw.
## [br][br]
## Budget: a few float ops per frame; the model transform is only written while a cue shows.

## Look and sounds.
@export var settings: NeedCueSettings
## Needs whose cues it shows.
@export var needs: NeedsComponent
## The [code]Model[/code] node holding the species model.
@export var model_root: Node3D

var _pant: AudioStreamPlayer3D
var _growl: AudioStreamPlayer3D
var _model: Node3D
var _base_scale := Vector3.ONE
var _base_rotation := Vector3.ZERO
var _pant_weight: float = 0.0
var _shiver_weight: float = 0.0
var _time: float = 0.0
var _growl_in: float = 0.0
var _hungry: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = settings.seed_value
	_pant = _player(_looping(settings.pant_stream), settings.pant_volume_db)
	_growl = _player(settings.growl_stream, settings.growl_volume_db)


func _process(delta: float) -> void:
	advance(delta)


## Advances the cues by [param delta] seconds.
func advance(delta: float) -> void:
	if needs == null or needs.effects == null:
		return
	var cues := needs.effects.cues()
	var step := settings.ease_per_second * delta
	_pant_weight = move_toward(_pant_weight, 1.0 if cues.has(&"pant") else 0.0, step)
	_shiver_weight = move_toward(_shiver_weight, 1.0 if cues.has(&"shiver") else 0.0, step)
	_time += delta
	_update_pant()
	_update_growl(cues.has(&"growl"), delta)
	_update_model()


## How strongly the animal pants now (0…1).
func pant_weight() -> float:
	return _pant_weight


## How strongly it shivers now (0…1).
func shiver_weight() -> float:
	return _shiver_weight


## The panting player (tests and tools).
func pant_player() -> AudioStreamPlayer3D:
	return _pant


## The rumble player (tests and tools).
func growl_player() -> AudioStreamPlayer3D:
	return _growl


# A looping copy of [param stream] (WAVs import as one-shots).
static func _looping(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return stream
	wav = wav.duplicate() as AudioStreamWAV
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return wav


func _player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = settings.bus
	add_child(player)
	return player


func _update_pant() -> void:
	if _pant_weight <= 0.0:
		if _pant.playing:
			_pant.stop()
		return
	_pant.volume_db = settings.pant_volume_db + linear_to_db(_pant_weight)
	if not _pant.playing and _pant.stream != null:
		_pant.play()


func _update_growl(hungry: bool, delta: float) -> void:
	if hungry and not _hungry:
		_growl_in = settings.growl_first
	_hungry = hungry
	if not hungry:
		return
	_growl_in -= delta
	if _growl_in <= 0.0:
		if _growl.stream != null:
			_growl.play()
		_growl_in = _rng.randf_range(settings.growl_every.x, settings.growl_every.y)


func _update_model() -> void:
	if _model == null:
		if model_root == null or model_root.get_child_count() == 0:
			return
		_model = model_root.get_child(0) as Node3D
		_base_scale = _model.scale
		_base_rotation = _model.rotation
	if _pant_weight <= 0.0 and _shiver_weight <= 0.0:
		if _model.scale != _base_scale or _model.rotation != _base_rotation:
			_model.scale = _base_scale
			_model.rotation = _base_rotation
		return
	var breath := sin(TAU * settings.pant_hz * _time) * settings.pant_breath * _pant_weight
	_model.scale = Vector3(_base_scale.x, _base_scale.y * (1.0 + breath), _base_scale.z)
	var shake := (
		sin(TAU * settings.shiver_hz * _time) + 0.5 * sin(TAU * settings.shiver_hz * 1.7 * _time)
	)
	var roll := deg_to_rad(settings.shiver_degrees) * _shiver_weight * shake / 1.5
	_model.rotation = _base_rotation + Vector3(roll * 0.4, 0.0, roll)
