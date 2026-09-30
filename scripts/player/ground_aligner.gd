class_name GroundAligner
extends Node
## Tilts the animal's visual model to follow the ground: four rays under the paws give front/
## back and left/right heights, turned into pitch and roll, clamped to the species' maximum and
## smoothed. Only the model pivot rotates; the [CharacterBody3D] and its capsule stay upright.
## In the air, while swimming or when [member level] is set, the model eases back to level.
## [br][br]
## Budget: four ray casts every [member probe_interval] physics ticks (smoothing runs every
## tick towards the last target); the query and height buffers are reused.

## Physics layers the probes hit (the world layer).
const WORLD_MASK: int = 1
## Probe start above the paws and length below them (m).
const PROBE_UP: float = 0.6
const PROBE_DOWN: float = 1.2

## Body whose ground is probed.
@export var body: CharacterBody3D
## Movement (species data, grounded state).
@export var movement: MovementComponent
## Node rotated to show the tilt (the model pivot).
@export var pivot: Node3D
## Physics ticks between ground probes (1 = every tick; fauna probe less often).
@export_range(1, 30) var probe_interval: int = 1

## Current (smoothed) tilt in radians: x = pitch (nose up > 0), y = roll (left side up > 0).
var tilt: Vector2 = Vector2.ZERO
## Whether the model should stay level regardless of the ground (e.g. while swimming).
var level: bool = false

var _target: Vector2 = Vector2.ZERO
var _ticks: int = 0
var _query := PhysicsRayQueryParameters3D.new()
var _heights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _ready() -> void:
	_query.collision_mask = WORLD_MASK
	if body != null:
		_query.exclude = [body.get_rid()]
	_ticks = randi() % probe_interval  # stagger agents


func _physics_process(delta: float) -> void:
	var species := movement.species
	if species == null or species.max_tilt_degrees <= 0.0:
		return
	if movement.is_grounded() and not level and not movement.swimming:
		_ticks -= 1
		if _ticks <= 0:
			_ticks = probe_interval
			_target = tilt_from_heights(_probe_heights(species), species)
	else:
		_target = Vector2.ZERO
	tilt = tilt.lerp(_target, 1.0 - exp(-species.tilt_smoothing * delta))
	pivot.rotation = Vector3(tilt.x, 0.0, -tilt.y)
	body.rotation.x = 0.0
	body.rotation.z = 0.0


## Pitch and roll (radians) from ground heights under the paws [front-left, front-right,
## back-left, back-right], clamped to the species' maximum tilt.
static func tilt_from_heights(heights: PackedFloat32Array, species: AnimalSpecies) -> Vector2:
	var front := (heights[0] + heights[1]) * 0.5
	var back := (heights[2] + heights[3]) * 0.5
	var left := (heights[0] + heights[2]) * 0.5
	var right := (heights[1] + heights[3]) * 0.5
	var pitch := atan2(front - back, 2.0 * species.paw_half_length)
	var roll := atan2(left - right, 2.0 * species.paw_half_width)
	var limit := deg_to_rad(species.max_tilt_degrees)
	return Vector2(clampf(pitch, -limit, limit), clampf(roll, -limit, limit))


func _probe_heights(species: AnimalSpecies) -> PackedFloat32Array:
	var space := body.get_world_3d().direct_space_state
	var basis := Basis(Vector3.UP, body.global_rotation.y)
	var l := species.paw_half_length
	var w := species.paw_half_width
	# Forward is -Z: front paws at -l, left paws at -w.
	for i in 4:
		var offset := Vector3(-w if i % 2 == 0 else w, 0.0, -l if i < 2 else l)
		var foot := body.global_position + basis * offset
		_query.from = foot + Vector3.UP * PROBE_UP
		_query.to = foot + Vector3.DOWN * PROBE_DOWN
		var hit := space.intersect_ray(_query)
		_heights[i] = (
			(hit["position"] as Vector3).y if not hit.is_empty() else body.global_position.y
		)
	return _heights
