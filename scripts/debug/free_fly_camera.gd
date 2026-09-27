class_name FreeFlyCamera
extends Camera3D
## Debug fly camera: WASD flies along the view direction, the captured mouse looks around,
## [code]sprint[/code] boosts and the zoom actions change the base speed. Only reacts while
## [member active]. Can also fly on autopilot for automated streaming probes.

## Speeds and look sensitivity.
@export var settings: FreeFlyCameraSettings

## Whether the camera is the current one and reads input.
var active: bool = false:
	set = set_active
## Current base speed (m/s), adjusted with the mouse wheel.
var speed: float = 0.0

var _autopilot_velocity: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	# Moved in _process (not physics): opt out of physics interpolation like CameraRig.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if settings == null or not settings.is_valid():
		push_error("FreeFlyCamera %s: invalid settings" % get_path())
		set_process(false)
		return
	speed = settings.base_speed
	set_active(active)


func _unhandled_input(event: InputEvent) -> void:
	if not active or settings == null:
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(motion.relative)
	elif event.is_action_pressed(&"camera_zoom_in"):
		speed = step_speed(speed, 1, settings)
	elif event.is_action_pressed(&"camera_zoom_out"):
		speed = step_speed(speed, -1, settings)


func _process(delta: float) -> void:
	if not active:
		return
	if _autopilot_velocity != Vector3.ZERO:
		global_position += _autopilot_velocity * delta
		return
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var boost := settings.boost if Input.is_action_pressed(&"sprint") else 1.0
	global_position += fly_velocity(input, global_basis, speed * boost) * delta


## Activates or deactivates the camera (becomes/stops being the current camera).
func set_active(value: bool) -> void:
	active = value
	if is_inside_tree():
		current = value


## Rotates the view by a mouse delta (pixels).
func look(relative: Vector2) -> void:
	_yaw = wrapf(_yaw - relative.x * settings.mouse_sensitivity, -PI, PI)
	_pitch = clampf(_pitch - relative.y * settings.mouse_sensitivity, -PI * 0.49, PI * 0.49)
	rotation = Vector3(_pitch, _yaw, 0.0)


## Places the camera at [param xform], keeping its look angles consistent.
func take_transform(xform: Transform3D) -> void:
	global_transform = xform
	_yaw = rotation.y
	_pitch = rotation.x
	rotation = Vector3(_pitch, _yaw, 0.0)


## Flies at a constant world velocity, ignoring input, until [method stop_autopilot].
func start_autopilot(velocity: Vector3) -> void:
	_autopilot_velocity = velocity


## Returns control to input.
func stop_autopilot() -> void:
	_autopilot_velocity = Vector3.ZERO


## World velocity for a move input (Input.get_vector convention) along [param basis].
static func fly_velocity(input: Vector2, basis: Basis, fly_speed: float) -> Vector3:
	var direction := basis.x * input.x + basis.z * input.y
	return direction.limit_length(1.0) * fly_speed


## Speed after [param notches] wheel notches (positive = faster), clamped to the limits.
static func step_speed(current: float, notches: int, cam_settings: FreeFlyCameraSettings) -> float:
	var next := current * pow(cam_settings.speed_step, notches)
	return clampf(next, cam_settings.min_speed, cam_settings.max_speed)
