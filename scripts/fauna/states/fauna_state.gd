class_name FaunaState
extends State
## Base class for fauna behaviour states: they write the agent's movement intent (world
## directions) and drive its [MovementComponent] like the player's states do.

const WANDER: StringName = &"Wander"

## Movement driven by this state.
@export var movement: MovementComponent


## The agent this state belongs to.
func agent() -> FaunaAgent:
	return actor as FaunaAgent


## Sets the intent to move towards [param point] ([param pace] 0…1: walk below ~0.5, trot at 1).
func steer_towards(point: Vector3, pace: float) -> void:
	var to := point - agent().global_position
	var flat := Vector2(to.x, to.z)
	movement.move_input = flat.normalized() * pace if flat.length() > 0.01 else Vector2.ZERO


## Runs one ground-movement tick with the current intent.
func ground_tick(delta: float) -> void:
	movement.apply_ground_movement(delta)
	movement.apply_gravity(delta)
	movement.move()
