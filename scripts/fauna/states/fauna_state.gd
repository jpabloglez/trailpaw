class_name FaunaState
extends State
## Base class for fauna behaviour states: they write the agent's movement intent (world
## directions, steered around obstacles, water and steep ground) and drive its
## [MovementComponent] like the player's states do. A state reports [method is_done] when its
## bout is over; the [FaunaBrain] then decides what comes next.

const WANDER: StringName = &"Wander"
## Seconds a chosen (clear) direction is kept before probing again.
const STEER_INTERVAL: float = 0.1

## Movement driven by this state.
@export var movement: MovementComponent

var _steer_left: float = 0.0
var _steer_dir: Vector3 = Vector3.ZERO


## The agent this state belongs to.
func agent() -> FaunaAgent:
	return actor as FaunaAgent


## Whether this bout of the behaviour is over.
func is_done() -> bool:
	return false


## Starts a new bout of the same behaviour (the brain chose it again).
func restart() -> void:
	enter(StringName(name))


## Sets the intent to move towards [param point] at [param pace] (0…1: walk below ~0.5, trot
## at 1), steering around what blocks the way and away from other animals.
func steer_towards(point: Vector3, pace: float) -> void:
	var to := point - agent().global_position
	to.y = 0.0
	steer_along(to.normalized() if to.length() > 0.01 else Vector3.ZERO, pace)


## Like [method steer_towards] with a direction.
func steer_along(direction: Vector3, pace: float) -> void:
	var brain := agent().brain
	var desired := direction
	if brain != null:
		desired = (desired + brain.separation).normalized()
	_steer_left -= get_physics_process_delta_time()
	if _steer_left <= 0.0 or desired.dot(_steer_dir) < 0.7:
		_steer_left = STEER_INTERVAL
		_steer_dir = FaunaSteering.clear_direction(desired, agent().is_clear)
	movement.move_input = Vector2(_steer_dir.x, _steer_dir.z) * pace


## Stands still (decelerating).
func stand() -> void:
	movement.move_input = Vector2.ZERO


## Runs one ground-movement tick with the current intent.
func ground_tick(delta: float) -> void:
	movement.apply_ground_movement(delta)
	movement.apply_gravity(delta)
	movement.move()
