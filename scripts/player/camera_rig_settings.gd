class_name CameraRigSettings
extends Resource
## Tunables for [CameraRig]. Lives under [code]data/camera/[/code].
##
## The player's sensitivity multiplier, invert-Y and field of view live in the
## [code]Settings[/code] autoload (Phase 10); these are the tuned defaults.
## Defaults are deliberately neutral: values come from data (see
## [method get_validation_errors]).

@export_group("Look")
## Orbit speed per pixel of mouse motion.
@export_range(0.0001, 0.02, 0.0001, "suffix:rad/px") var mouse_sensitivity: float = 0.0
## Invert vertical mouse look.
@export var invert_y: bool = false
## Lowest pitch (looking down). Negative values look down.
@export_range(-89.0, 0.0, 1.0, "suffix:°") var pitch_min_degrees: float = 0.0
## Highest pitch (looking up).
@export_range(-45.0, 60.0, 1.0, "suffix:°") var pitch_max_degrees: float = 0.0
## Pitch on start.
@export_range(-89.0, 60.0, 1.0, "suffix:°") var default_pitch_degrees: float = 0.0

@export_group("Zoom")
## Closest camera distance (spring arm length).
@export_range(0.5, 20.0, 0.1, "suffix:m") var zoom_min: float = 0.0
## Farthest camera distance.
@export_range(0.5, 50.0, 0.1, "suffix:m") var zoom_max: float = 0.0
## Distance change per wheel notch.
@export_range(0.05, 5.0, 0.05, "suffix:m") var zoom_step: float = 0.0
## Distance on start.
@export_range(0.5, 50.0, 0.1, "suffix:m") var zoom_default: float = 0.0
## How fast the distance eases towards the zoom target (higher is snappier).
@export_range(0.1, 50.0, 0.1, "suffix:1/s") var zoom_smoothing: float = 0.0

@export_group("Follow")
## Height of the orbit pivot above the target's origin.
@export_range(0.0, 5.0, 0.05, "suffix:m") var pivot_height: float = 0.0
## How fast the rig catches up with the target (higher means less lag).
@export_range(0.1, 50.0, 0.1, "suffix:1/s") var follow_smoothing: float = 0.0
## Radius of the spring-arm probe that keeps the camera out of walls.
@export_range(0.01, 1.0, 0.01, "suffix:m") var collision_margin: float = 0.0

@export_group("Auto-recentre")
## Seconds without mouse look before the camera swings behind the moving target.
@export_range(0.0, 10.0, 0.1, "suffix:s") var recentre_delay: float = 0.0
## How fast the camera swings behind the target.
@export_range(0.1, 20.0, 0.1, "suffix:1/s") var recentre_speed: float = 0.0
## Target speed required before auto-recentring kicks in.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var recentre_min_speed: float = 0.0

@export_group("Landing shake")
## Falls slower than this do not shake the camera (m/s).
@export_range(0.0, 50.0, 0.5, "suffix:m/s") var shake_min_fall: float = 6.0
## Falls this fast or faster shake it fully (m/s).
@export_range(0.0, 50.0, 0.5, "suffix:m/s") var shake_max_fall: float = 14.0
## Largest camera offset (m) and roll (degrees) of a full shake.
@export_range(0.0, 1.0, 0.005, "suffix:m") var shake_offset: float = 0.08
@export_range(0.0, 10.0, 0.1, "suffix:°") var shake_roll: float = 1.5
## Seconds a shake takes to die out.
@export_range(0.05, 3.0, 0.05, "suffix:s") var shake_duration: float = 0.3


## Returns human-readable problems with the tunables; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if mouse_sensitivity <= 0.0:
		errors.append("mouse_sensitivity must be > 0")
	if pitch_min_degrees >= pitch_max_degrees:
		errors.append("pitch_min_degrees must be < pitch_max_degrees")
	if default_pitch_degrees < pitch_min_degrees or default_pitch_degrees > pitch_max_degrees:
		errors.append("default_pitch_degrees must be within the pitch limits")
	if zoom_min <= 0.0 or zoom_min >= zoom_max:
		errors.append("zoom limits must satisfy 0 < zoom_min < zoom_max")
	if zoom_default < zoom_min or zoom_default > zoom_max:
		errors.append("zoom_default must be within the zoom limits")
	if zoom_step <= 0.0 or zoom_smoothing <= 0.0 or follow_smoothing <= 0.0:
		errors.append("zoom_step, zoom_smoothing and follow_smoothing must be > 0")
	if collision_margin <= 0.0:
		errors.append("collision_margin must be > 0")
	if recentre_speed <= 0.0:
		errors.append("recentre_speed must be > 0")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
