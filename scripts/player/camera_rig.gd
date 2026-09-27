class_name CameraRig
extends Node3D
## Third-person orbit camera: follows a target with lag, orbits with the captured mouse,
## zooms with the wheel, avoids walls with a [SpringArm3D] and swings back behind the
## target while it moves and the player is not looking around.
##
## Runs in [method _process] on the target's interpolated transform (physics
## interpolation is on project-wide) so the camera stays smooth above 60 Hz.
## The cursor is captured on click and released with [code]pause[/code] (Esc).

## World physics layer the spring arm collides with (see ARCHITECTURE §4.2).
const WORLD_COLLISION_MASK: int = 1

## Node to follow and orbit around.
@export var target: Node3D
## Look, zoom, follow and recentre tunables.
@export var settings: CameraRigSettings

var _zoom_target: float = 0.0
var _time_since_look: float = 0.0
var _previous_goal: Vector3 = Vector3.ZERO

## The rig's camera.
@onready var camera: Camera3D = %Camera3D
@onready var _yaw: Node3D = %Yaw
@onready var _pitch: Node3D = %Pitch
@onready var _arm: SpringArm3D = %SpringArm3D


func _ready() -> void:
	if settings == null or not settings.is_valid():
		var problems := settings.get_validation_errors() if settings else PackedStringArray()
		push_error("CameraRig %s: invalid settings %s" % [get_path(), problems])
		set_process(false)
		return
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var probe := SphereShape3D.new()
	probe.radius = settings.collision_margin
	_arm.shape = probe
	_arm.collision_mask = WORLD_COLLISION_MASK
	_zoom_target = settings.zoom_default
	_arm.spring_length = settings.zoom_default
	_pitch.rotation.x = deg_to_rad(settings.default_pitch_degrees)
	if target != null:
		_previous_goal = _goal_position()
		global_position = _previous_goal
		_yaw.rotation.y = target.global_rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if settings == null:
		return
	var mouse_button := event as InputEventMouseButton
	var is_click := (
		mouse_button != null
		and mouse_button.pressed
		and mouse_button.button_index == MOUSE_BUTTON_LEFT
	)
	if is_click and not _is_mouse_captured():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _is_mouse_captured():
		apply_look((event as InputEventMouseMotion).relative)
	elif event.is_action_pressed(&"camera_zoom_in"):
		_zoom_target = step_zoom(_zoom_target, -settings.zoom_step, settings)
	elif event.is_action_pressed(&"camera_zoom_out"):
		_zoom_target = step_zoom(_zoom_target, settings.zoom_step, settings)


func _process(delta: float) -> void:
	if target == null:
		return
	var goal := _goal_position()
	var target_speed := Vector2(goal.x - _previous_goal.x, goal.z - _previous_goal.z).length()
	target_speed /= maxf(delta, 1e-5)
	_previous_goal = goal
	global_position = global_position.lerp(goal, smoothing_weight(settings.follow_smoothing, delta))
	_arm.spring_length = lerpf(
		_arm.spring_length, _zoom_target, smoothing_weight(settings.zoom_smoothing, delta)
	)
	_time_since_look += delta
	if _time_since_look >= settings.recentre_delay and target_speed >= settings.recentre_min_speed:
		_yaw.rotation.y = recentre_yaw(
			_yaw.rotation.y, target.global_rotation.y, settings.recentre_speed, delta
		)


## Orbits by a mouse motion delta (pixels). Resets the auto-recentre timer.
func apply_look(relative: Vector2) -> void:
	var vertical := relative.y * (-1.0 if settings.invert_y else 1.0)
	_yaw.rotation.y = wrapf(_yaw.rotation.y - relative.x * settings.mouse_sensitivity, -PI, PI)
	_pitch.rotation.x = clamp_pitch(
		_pitch.rotation.x - vertical * settings.mouse_sensitivity, settings
	)
	_time_since_look = 0.0


## Current zoom target (spring arm length the camera eases towards).
func zoom_target() -> float:
	return _zoom_target


## Current orbit yaw (radians).
func yaw() -> float:
	return _yaw.rotation.y


## Current orbit pitch (radians, negative looks down).
func pitch() -> float:
	return _pitch.rotation.x


## Clamps a pitch angle (radians) to the configured limits.
static func clamp_pitch(pitch_radians: float, rig_settings: CameraRigSettings) -> float:
	return clampf(
		pitch_radians,
		deg_to_rad(rig_settings.pitch_min_degrees),
		deg_to_rad(rig_settings.pitch_max_degrees)
	)


## Returns [param current] + [param amount], clamped to the zoom limits.
static func step_zoom(current: float, amount: float, rig_settings: CameraRigSettings) -> float:
	return clampf(current + amount, rig_settings.zoom_min, rig_settings.zoom_max)


## Eases [param current_yaw] towards [param target_yaw] along the shortest arc.
static func recentre_yaw(current_yaw: float, target_yaw: float, rate: float, delta: float) -> float:
	return wrapf(lerp_angle(current_yaw, target_yaw, smoothing_weight(rate, delta)), -PI, PI)


## Frame-rate independent exponential smoothing weight for [method lerp].
static func smoothing_weight(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


func _goal_position() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * settings.pivot_height


func _is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
