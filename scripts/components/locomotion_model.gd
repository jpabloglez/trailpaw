class_name LocomotionModel
extends RefCounted
## Pure locomotion maths for quadrupeds: camera-relative direction, arc turning,
## acceleration and gait selection. No nodes, no input, no physics: fully unit-testable.
##
## Conventions: forward is [code]-Z[/code]; yaw 0 faces [code]-Z[/code]; input vectors
## follow [method Input.get_vector] with [code]y < 0[/code] meaning "forward".
## [br][br]
## Budget: a handful of float ops per call; no allocations (value types only).

## Locomotion gait, derived from the current horizontal speed.
enum Gait { IDLE, WALK, TROT, RUN }

## Below this horizontal speed the animal counts as standing still.
const IDLE_SPEED: float = 0.05
## Squared length under which a direction is treated as "no direction".
const MIN_DIRECTION_SQ: float = 1e-6


## Converts a 2D move input into a world-space direction on the XZ plane, relative to the
## camera. The result's length equals the input strength, capped at 1.
static func camera_relative_direction(input: Vector2, camera_basis: Basis) -> Vector3:
	var forward := Vector3(-camera_basis.z.x, 0.0, -camera_basis.z.z)
	if forward.length_squared() < MIN_DIRECTION_SQ:
		# Camera looks straight up/down: its up vector points "forward" on screen.
		forward = Vector3(camera_basis.y.x, 0.0, camera_basis.y.z)
	var right := Vector3(camera_basis.x.x, 0.0, camera_basis.x.z)
	var direction := right.normalized() * input.x + forward.normalized() * -input.y
	return direction.limit_length(1.0)


## Yaw (radians) that makes an actor face [param direction].
static func yaw_for_direction(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Unit forward vector for a given yaw.
static func forward_for_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Maximum yaw rate at [param speed]: tight turns when slow, wide arcs when running.
static func turn_rate(speed: float, species: AnimalSpecies) -> float:
	var t := clampf(speed / species.run_speed, 0.0, 1.0)
	return lerpf(species.turn_rate_slow, species.turn_rate_fast, t)


## Rotates [param current_yaw] towards [param desired_direction], limited by the turn
## rate. [param control] scales the rate (1 on the ground, [code]air_control[/code] in
## the air). Returns the new yaw, wrapped to [-PI, PI].
static func step_heading(
	current_yaw: float,
	desired_direction: Vector3,
	speed: float,
	species: AnimalSpecies,
	delta: float,
	control: float = 1.0
) -> float:
	if desired_direction.length_squared() < MIN_DIRECTION_SQ:
		return current_yaw
	var error := heading_error(current_yaw, desired_direction)
	var max_step := turn_rate(speed, species) * control * delta
	return wrapf(current_yaw + clampf(error, -max_step, max_step), -PI, PI)


## Signed angle (radians, [-PI, PI]) from [param yaw] to [param desired_direction].
static func heading_error(yaw: float, desired_direction: Vector3) -> float:
	if desired_direction.length_squared() < MIN_DIRECTION_SQ:
		return 0.0
	return wrapf(yaw_for_direction(desired_direction) - yaw, -PI, PI)


## Speed the actor should aim for. Full input trots, sprint runs; facing away from the
## desired direction lowers the target so sharp turns become arcs.
static func target_speed(
	input_strength: float, sprint: bool, error: float, species: AnimalSpecies
) -> float:
	if input_strength <= 0.0:
		return 0.0
	var base := species.run_speed if sprint else species.trot_speed
	var slowdown := clampf(1.0 - species.turn_slowdown * absf(error) / PI, 0.0, 1.0)
	return base * clampf(input_strength, 0.0, 1.0) * slowdown


## Moves [param current] towards [param target] using the species' acceleration or
## deceleration. The result is always within [0, run_speed].
static func step_speed(
	current: float, target: float, species: AnimalSpecies, delta: float, control: float = 1.0
) -> float:
	var rate := species.acceleration if target > current else species.deceleration
	var next := move_toward(current, target, rate * control * delta)
	return clampf(next, 0.0, species.run_speed)


## Gait for a horizontal speed. Boundaries sit halfway between the gait speeds so the
## label is stable around each target speed.
static func gait_for_speed(speed: float, species: AnimalSpecies) -> Gait:
	if speed < IDLE_SPEED:
		return Gait.IDLE
	if speed < (species.walk_speed + species.trot_speed) * 0.5:
		return Gait.WALK
	if speed < (species.trot_speed + species.run_speed) * 0.5:
		return Gait.TROT
	return Gait.RUN


## Initial vertical velocity that reaches [param height] under [param gravity].
static func jump_velocity(height: float, gravity: float) -> float:
	return sqrt(2.0 * gravity * height)
