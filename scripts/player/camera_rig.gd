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
## The target's movement: hard landings shake the camera a little (optional).
@export var movement: MovementComponent

var _zoom_target: float = 0.0
var _time_since_look: float = 0.0
var _previous_goal: Vector3 = Vector3.ZERO
var _trauma: float = 0.0
var _shake_time: float = 0.0

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
	add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	EventBus.origin_shifted.connect(_on_origin_shifted)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var probe := SphereShape3D.new()
	probe.radius = settings.collision_margin
	_arm.shape = probe
	_arm.collision_mask = WORLD_COLLISION_MASK
	_zoom_target = settings.zoom_default
	_arm.spring_length = settings.zoom_default
	_pitch.rotation.x = deg_to_rad(settings.default_pitch_degrees)
	camera.fov = Settings.fov
	Settings.changed.connect(_on_settings_changed)
	if movement != null:
		movement.landed.connect(on_landed)
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
	_apply_shake(delta)
	_time_since_look += delta
	if _time_since_look >= settings.recentre_delay and target_speed >= settings.recentre_min_speed:
		_yaw.rotation.y = recentre_yaw(
			_yaw.rotation.y, target.global_rotation.y, settings.recentre_speed, delta
		)


## A landing at [param fall_speed] m/s: shakes the camera in proportion above
## [member CameraRigSettings.shake_min_fall], unless the player turned shaking off.
func on_landed(fall_speed: float) -> void:
	if not Settings.camera_shake or fall_speed < settings.shake_min_fall:
		return
	var span := maxf(settings.shake_max_fall - settings.shake_min_fall, 0.01)
	_trauma = maxf(_trauma, clampf((fall_speed - settings.shake_min_fall) / span, 0.2, 1.0))


## A short jolt of [param amount] (0…1), e.g. when the fox is shooed, unless shaking is off.
func jolt(amount: float) -> void:
	if Settings.camera_shake:
		_trauma = maxf(_trauma, clampf(amount, 0.0, 1.0))


## How strong the shake is now (0 … 1).
func trauma() -> float:
	return _trauma


func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0 or camera.rotation.z != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			camera.rotation.z = 0.0
		return
	_shake_time += delta
	var amount := _trauma * _trauma  # eases out
	camera.h_offset = sin(_shake_time * 61.0) * settings.shake_offset * amount
	camera.v_offset = sin(_shake_time * 47.0 + 1.3) * settings.shake_offset * amount
	camera.rotation.z = deg_to_rad(sin(_shake_time * 53.0 + 0.7) * settings.shake_roll * amount)
	_trauma = maxf(0.0, _trauma - delta / settings.shake_duration)


## Orbits by a mouse motion delta (pixels). Resets the auto-recentre timer.
func apply_look(relative: Vector2) -> void:
	# The player's Settings scale the tuned sensitivity and may invert the vertical look.
	var inverted := settings.invert_y != Settings.invert_y
	var vertical := relative.y * (-1.0 if inverted else 1.0)
	var speed := settings.mouse_sensitivity * Settings.mouse_sensitivity
	_yaw.rotation.y = wrapf(_yaw.rotation.y - relative.x * speed, -PI, PI)
	_pitch.rotation.x = clamp_pitch(_pitch.rotation.x - vertical * speed, settings)
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


func _on_origin_shifted(offset: Vector3) -> void:
	# The rig itself is shifted by FloatingOrigin; keep the cached goal consistent so the
	# jump is not mistaken for target movement (which would trigger auto-recentre).
	_previous_goal -= offset


func _goal_position() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * settings.pivot_height


func _is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _on_settings_changed(_key: StringName) -> void:
	camera.fov = Settings.fov
