class_name FootstepAudio
extends Node3D
## Plays a footstep sound on each [signal AnimationController.footstep]: grass, bare ground
## (by biome) or water (when wading), a random clip at a random pitch, from a small pool of
## positional players on the SFX bus.
## [br][br]
## Budget: nothing per frame; per step one pool lookup and one play.

## Surfaces.
enum Surface { GRASS, GROUND, WATER }

## Players in the pool (a step rarely overlaps more than two).
const POOL: int = 3

## Sounds and mix.
@export var settings: FootstepSettings
## Emits the steps.
@export var animation: AnimationController
## Water depth over the paws.
@export var movement: MovementComponent

var _players: Array[AudioStreamPlayer3D] = []
var _next: int = 0
var _last_step_frame: int = -100000
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for i in POOL:
		var player := AudioStreamPlayer3D.new()
		player.bus = settings.bus
		player.unit_size = 4.0
		add_child(player)
		_players.append(player)
	if animation != null:
		animation.footstep.connect(func(_paw: StringName) -> void: step())


## Surface under the paws now.
func surface() -> Surface:
	if movement != null and movement.water_depth() > settings.wading_depth:
		return Surface.WATER
	if settings.ground_biomes.has(GameState.current_biome):
		return Surface.GROUND
	return Surface.GRASS


## Plays one step (skipped when too close to the previous one). Returns the player used, or
## null.
func step() -> AudioStreamPlayer3D:
	# Game time (physics frames), not wall-clock time: follows pauses and slow frames.
	var now := Engine.get_physics_frames()
	var min_frames := int(settings.min_interval * Engine.physics_ticks_per_second)
	if now - _last_step_frame < min_frames:
		return null
	_last_step_frame = now
	var where := surface()
	var clips: Array[AudioStream] = (
		[settings.grass, settings.ground, settings.water][where] as Array[AudioStream]
	)
	if clips.is_empty():
		return null
	var player := _players[_next]
	_next = (_next + 1) % POOL
	player.stream = clips[_rng.randi() % clips.size()]
	player.pitch_scale = _rng.randf_range(settings.pitch.x, settings.pitch.y)
	player.volume_db = settings.volume_db[where]
	player.play()
	return player
