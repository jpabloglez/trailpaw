class_name AnimalSpawner
extends Node
## Keeps the player animal parked (processing disabled) until the terrain under it has
## collision, then drops it just above the ground. Shared by the world scene and the terrain
## sandbox.
## [br][br]
## Budget: one [method WorldStreamer.is_ready_at] check per frame while parked.

## The animal was released onto the ground.
signal released

## Height above the terrain the animal is dropped from (m).
const CLEARANCE: float = 0.5

## The animal.
@export var animal: Animal
## Terrain (readiness and settings).
@export var streamer: WorldStreamer
## Whether it releases the animal by itself once the ground is ready (the sandbox turns this off
## while free-flying).
@export var auto_release: bool = true

var _parked: bool = false
var _sampler: HeightSampler


func _process(_delta: float) -> void:
	if _parked and auto_release and streamer.is_ready_at(animal.position):
		release()


## Parks the animal (no physics, no input) until [method release].
func park() -> void:
	_parked = true
	animal.process_mode = Node.PROCESS_MODE_DISABLED


## Drops the animal onto the terrain under it and lets it move.
func release() -> void:
	if _sampler == null:
		_sampler = HeightSampler.new(streamer.terrain, GameState.world_seed)
	var absolute: Vector3 = GameState.absolute_position(animal.position)
	var ground := _sampler.height_at(absolute.x, absolute.z)
	animal.position.y = maxf(animal.position.y, ground) if is_on_water(ground) else ground
	animal.position.y += CLEARANCE
	animal.velocity = Vector3.ZERO
	animal.reset_physics_interpolation()
	_parked = false
	animal.process_mode = Node.PROCESS_MODE_INHERIT
	released.emit()


## Whether the animal is parked.
func is_parked() -> bool:
	return _parked


## Whether ground at [param height] lies under the water (keep a floating animal afloat).
func is_on_water(height: float) -> bool:
	return height < GameState.water_level
