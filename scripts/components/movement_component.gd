class_name MovementComponent
extends Node
## Drives its parent [CharacterBody3D] from a movement *intent* using [LocomotionModel].
##
## Whoever controls the body (player input now, fauna AI later) writes [member move_input],
## [member sprint] and calls [method request_jump]. States of a [StateMachine] decide
## which [code]apply_*[/code] methods run each tick and then call [method move].
## [br][br]
## Budget: one [method CharacterBody3D.move_and_slide] per tick; no per-frame allocations.

## Squared input length below which there is no move intent.
const INPUT_DEADZONE_SQ: float = 0.01
## A jump request stays valid for this many physics frames (covers node update order).
const JUMP_REQUEST_FRAMES: int = 1
## Vertical speed cap of the buoyancy pull (m/s): gentle bobbing, no launch.
const MAX_BUOYANCY_SPEED: float = 3.0

## Locomotion tunables. Must be valid (see [method AnimalSpecies.get_validation_errors]).
@export var species: AnimalSpecies

## Desired movement, as returned by [method Input.get_vector] (y < 0 is forward).
var move_input: Vector2 = Vector2.ZERO
## Whether the controller wants to run.
var sprint: bool = false
## Whether the body is swimming (set by the swim state).
var swimming: bool = false

var _body: CharacterBody3D
var _gravity: float = 0.0
var _speed: float = 0.0
var _jump_request_frame: int = -1000


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("MovementComponent must be a child of a CharacterBody3D (%s)" % get_path())
		return
	if species == null:
		push_error("MovementComponent %s: no species assigned" % get_path())
		return
	if not species.is_valid():
		var problems := species.get_validation_errors()
		push_error("MovementComponent %s: invalid species %s" % [get_path(), problems])
		return
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	_body.floor_max_angle = deg_to_rad(species.max_slope_degrees)


## Asks for a jump. It is consumed by [method consume_jump_request] within
## [constant JUMP_REQUEST_FRAMES] physics frames, otherwise it is dropped.
func request_jump() -> void:
	_jump_request_frame = Engine.get_physics_frames()


## Returns [code]true[/code] once per valid jump request.
func consume_jump_request() -> bool:
	var fresh := Engine.get_physics_frames() - _jump_request_frame <= JUMP_REQUEST_FRAMES
	_jump_request_frame = -1000
	return fresh


## Whether the controller is asking to move.
func has_move_input() -> bool:
	return move_input.length_squared() > INPUT_DEADZONE_SQ


## Whether the body stood on a floor after the last [method move].
func is_grounded() -> bool:
	return _body.is_on_floor()


## Current vertical velocity (m/s, positive is up).
func vertical_speed() -> float:
	return _body.velocity.y


## Current horizontal speed along the heading (m/s).
func horizontal_speed() -> float:
	return _speed


## Gait matching the current horizontal speed.
func gait() -> LocomotionModel.Gait:
	return LocomotionModel.gait_for_speed(_speed, species)


## Water depth over the paws (m); 0 or less on dry land.
func water_depth() -> float:
	return GameState.water_level - _body.global_position.y


## Whether the water is deep enough to start swimming.
func should_start_swimming() -> bool:
	return species.can_swim() and water_depth() > species.swim_enter_depth


## Whether the animal stands on the bottom in shallow enough water to stop swimming.
func should_stop_swimming() -> bool:
	return water_depth() < species.swim_exit_depth and _body.is_on_floor()


## Swimming: slower horizontal movement and buoyancy towards the floating height.
func apply_swim_movement(delta: float) -> void:
	_step_horizontal(delta, 1.0, species.swim_speed_factor)
	var float_height := GameState.water_level - species.float_depth
	var pull := (float_height - _body.global_position.y) * species.buoyancy
	_body.velocity.y = clampf(pull, -MAX_BUOYANCY_SPEED, MAX_BUOYANCY_SPEED)


## Full-control horizontal movement: turning in arcs and accelerating along the heading.
func apply_ground_movement(delta: float) -> void:
	_step_horizontal(delta, 1.0)


## Reduced-control horizontal movement for jumps and falls.
func apply_air_movement(delta: float) -> void:
	_step_horizontal(delta, species.air_control)


## Accelerates the body downwards while it is off the floor.
func apply_gravity(delta: float) -> void:
	if not _body.is_on_floor():
		_body.velocity.y -= _gravity * delta


## Launches the body upwards to reach the species' jump height.
func perform_jump() -> void:
	_body.velocity.y = LocomotionModel.jump_velocity(species.jump_height, _gravity)


## Moves the body and keeps the tracked speed honest after collisions (walls stop you).
func move() -> void:
	_body.move_and_slide()
	var real_speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	_speed = minf(_speed, real_speed)


func _step_horizontal(delta: float, control: float, speed_factor: float = 1.0) -> void:
	var desired := LocomotionModel.camera_relative_direction(move_input, _camera_basis())
	var yaw := LocomotionModel.step_heading(
		_body.rotation.y, desired, _speed, species, delta, control
	)
	_body.rotation.y = yaw
	var error := LocomotionModel.heading_error(yaw, desired)
	var target := (
		LocomotionModel.target_speed(desired.length(), sprint, error, species) * speed_factor
	)
	_speed = LocomotionModel.step_speed(_speed, target, species, delta, control)
	var velocity := LocomotionModel.forward_for_yaw(yaw) * _speed
	_body.velocity.x = velocity.x
	_body.velocity.z = velocity.z


func _camera_basis() -> Basis:
	var camera := get_viewport().get_camera_3d()
	return camera.global_basis if camera != null else _body.global_basis
