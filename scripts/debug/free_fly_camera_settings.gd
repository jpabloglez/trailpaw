class_name FreeFlyCameraSettings
extends Resource
## Tunables for [FreeFlyCamera] (debug only). Values live in
## [code]data/debug/free_fly_camera.tres[/code].

## Speed on activation.
@export_range(0.1, 1000.0, 0.1, "suffix:m/s") var base_speed: float = 0.0
## Speed limits for the mouse-wheel adjustment.
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var min_speed: float = 0.0
## Speed limits for the mouse-wheel adjustment.
@export_range(1.0, 5000.0, 1.0, "suffix:m/s") var max_speed: float = 0.0
## Multiplier per wheel notch.
@export_range(1.01, 4.0, 0.01) var speed_step: float = 0.0
## Multiplier while [code]sprint[/code] is held.
@export_range(1.0, 20.0, 0.1) var boost: float = 0.0
## Look speed per pixel of mouse motion.
@export_range(0.0001, 0.02, 0.0001, "suffix:rad/px") var mouse_sensitivity: float = 0.0


## Returns human-readable problems with the tunables; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if min_speed <= 0.0 or min_speed > base_speed or base_speed > max_speed:
		errors.append("speeds must satisfy 0 < min_speed <= base_speed <= max_speed")
	if speed_step <= 1.0 or boost < 1.0 or mouse_sensitivity <= 0.0:
		errors.append("speed_step must be > 1, boost >= 1 and mouse_sensitivity > 0")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
