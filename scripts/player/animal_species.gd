class_name AnimalSpecies
extends Resource
## Data-only description of an animal species: locomotion tunables for Phase 1.
##
## Swapping species means swapping a [code].tres[/code] under [code]data/species/[/code];
## no code changes (ARCHITECTURE §4.1). Later phases add mesh, animations, needs and sounds.
## [br][br]
## Defaults are deliberately zero: every tunable must come from data, so a fresh
## [AnimalSpecies] is invalid until configured (see [method get_validation_errors]).

## Human-readable species name.
@export var display_name: String = ""

@export_group("Gaits")
## Target speed of the walk gait; speeds below this read as walking.
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var walk_speed: float = 0.0
## Default travel speed (full input, no sprint).
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var trot_speed: float = 0.0
## Top speed while sprinting. No movement may exceed it.
@export_range(0.1, 30.0, 0.1, "suffix:m/s") var run_speed: float = 0.0

@export_group("Acceleration")
## Rate at which horizontal speed rises towards the target.
@export_range(0.1, 100.0, 0.1, "suffix:m/s²") var acceleration: float = 0.0
## Rate at which horizontal speed falls when input is released or reduced.
@export_range(0.1, 100.0, 0.1, "suffix:m/s²") var deceleration: float = 0.0

@export_group("Turning")
## Maximum yaw rate when standing or walking. Quadrupeds turn tighter when slow.
@export_range(0.1, 20.0, 0.1, "suffix:rad/s") var turn_rate_slow: float = 0.0
## Maximum yaw rate at run speed; lower values give wider arcs.
@export_range(0.1, 20.0, 0.1, "suffix:rad/s") var turn_rate_fast: float = 0.0
## How much the target speed drops while facing away from the desired direction
## (0 = no slowdown, 1 = full stop when facing the opposite way).
@export_range(0.0, 1.0, 0.01) var turn_slowdown: float = 0.0

@export_group("Jump and slopes")
## Apex height of a standing jump.
@export_range(0.05, 5.0, 0.05, "suffix:m") var jump_height: float = 0.0
## Fraction of ground acceleration and turning available in the air.
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.0
## Steepest walkable slope; steeper surfaces behave like walls.
@export_range(1.0, 89.0, 0.5, "suffix:°") var max_slope_degrees: float = 0.0


## Returns human-readable problems with the tunables; empty when the species is valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if walk_speed <= 0.0:
		errors.append("walk_speed must be > 0")
	if not (walk_speed < trot_speed and trot_speed < run_speed):
		errors.append("speeds must satisfy walk_speed < trot_speed < run_speed")
	if acceleration <= 0.0 or deceleration <= 0.0:
		errors.append("acceleration and deceleration must be > 0")
	if turn_rate_fast <= 0.0 or turn_rate_fast > turn_rate_slow:
		errors.append("turn rates must satisfy 0 < turn_rate_fast <= turn_rate_slow")
	if turn_slowdown < 0.0 or turn_slowdown > 1.0:
		errors.append("turn_slowdown must be within [0, 1]")
	if jump_height <= 0.0:
		errors.append("jump_height must be > 0")
	if air_control < 0.0 or air_control > 1.0:
		errors.append("air_control must be within [0, 1]")
	if max_slope_degrees <= 0.0 or max_slope_degrees >= 90.0:
		errors.append("max_slope_degrees must be within (0, 90)")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
