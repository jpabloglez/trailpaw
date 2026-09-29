class_name AnimalSpecies
extends Resource
## Data-only description of an animal species: locomotion tunables for Phase 1.
##
## Swapping species means swapping a [code].tres[/code] under [code]data/species/[/code];
## no code changes (ARCHITECTURE §4.1). Later phases add mesh, animations, needs and sounds.
## [br][br]
## Defaults are deliberately zero: every tunable must come from data, so a fresh
## [AnimalSpecies] is invalid until configured (see [method get_validation_errors]).

## Animations every species with a model must provide (ROADMAP Phase 5; tired idle Phase 6).
const LOGICAL_ANIMATIONS: Array[StringName] = [
	&"idle",
	&"walk",
	&"trot",
	&"run",
	&"jump",
	&"fall",
	&"eat",
	&"drink",
	&"lie_down",
	&"sniff",
	&"swim",
	&"tired_idle",
]

## Human-readable species name.
@export var display_name: String = ""

@export_group("Model")
## Rigged, animated model (a [code].glb[/code] with a [Skeleton3D] and an [AnimationPlayer]).
## Empty for the Phase 1 placeholder box.
@export var model_scene: PackedScene
## Uniform scale applied to the model so it matches the collision capsule.
@export_range(0.001, 100.0, 0.001) var model_scale: float = 1.0
## Yaw applied to the model so it faces the game's forward (-Z).
@export_range(-180.0, 180.0, 1.0, "suffix:°") var model_yaw_degrees: float = 0.0

@export_group("Animation")
## Logical animation → clip name in the model's [AnimationPlayer]. Must cover
## [constant LOGICAL_ANIMATIONS] when a model is set.
@export var animations: Dictionary[StringName, String] = {}
## Logical animations played on a loop (the clips are not looped in the file).
@export var looping: Array[StringName] = []
## Logical animations that reuse a clip made for something else, with the reason. Only these
## may share clips or stand in for missing ones.
@export var animation_fallbacks: Dictionary[StringName, String] = {}
## Ground speed (m/s at [member model_scale]) each locomotion clip is authored for, measured
## with [ClipAnalysis]. Playback speed = movement speed / this, so paws do not slide.
@export var clip_ground_speeds: Dictionary[String, float] = {}
## Cap on locomotion playback speed-up; above it paws slide a little instead of the legs
## cycling frantically.
@export_range(1.0, 5.0, 0.05) var max_animation_time_scale: float = 1.0
## Paw bones (front left/right, back left/right) used for ground speed and footsteps.
@export var paw_bones: PackedStringArray = PackedStringArray()

@export_group("Ground alignment")
## Largest pitch/roll the model tilts to follow the ground.
@export_range(0.0, 60.0, 0.5, "suffix:°") var max_tilt_degrees: float = 0.0
## How fast the tilt follows the ground (higher is snappier).
@export_range(0.1, 50.0, 0.1, "suffix:1/s") var tilt_smoothing: float = 0.0
## Distance from the body centre to the front/back paws (ground probes).
@export_range(0.01, 5.0, 0.01, "suffix:m") var paw_half_length: float = 0.0
## Distance from the body centre to the left/right paws (ground probes).
@export_range(0.01, 2.0, 0.01, "suffix:m") var paw_half_width: float = 0.0

@export_group("Swimming")
## Water depth over the paws that starts swimming (0 = this species never swims).
@export_range(0.0, 5.0, 0.01, "suffix:m") var swim_enter_depth: float = 0.0
## Depth below which, standing on the bottom, swimming ends (< enter depth: hysteresis).
@export_range(0.0, 5.0, 0.01, "suffix:m") var swim_exit_depth: float = 0.0
## How deep the paws hang below the surface while floating.
@export_range(0.0, 5.0, 0.01, "suffix:m") var float_depth: float = 0.0
## Fraction of the land speed available while swimming.
@export_range(0.0, 1.0, 0.01) var swim_speed_factor: float = 0.0
## How fast buoyancy pulls the body to its floating height.
@export_range(0.0, 50.0, 0.1, "suffix:1/s") var buoyancy: float = 0.0

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
	if can_swim():
		if swim_exit_depth <= 0.0 or swim_exit_depth >= swim_enter_depth:
			errors.append("swim depths must satisfy 0 < swim_exit_depth < swim_enter_depth")
		if float_depth <= 0.0 or swim_speed_factor <= 0.0 or buoyancy <= 0.0:
			errors.append("float_depth, swim_speed_factor and buoyancy must be > 0")
	if model_scale <= 0.0:
		errors.append("model_scale must be > 0")
	if model_scene != null:
		for logical: StringName in LOGICAL_ANIMATIONS:
			if not animations.has(logical):
				errors.append("animations is missing '%s'" % logical)
		if paw_bones.size() != 4:
			errors.append("paw_bones must list 4 bones")
		if max_tilt_degrees <= 0.0 or tilt_smoothing <= 0.0:
			errors.append("max_tilt_degrees and tilt_smoothing must be > 0")
		if paw_half_length <= 0.0 or paw_half_width <= 0.0:
			errors.append("paw_half_length and paw_half_width must be > 0")
	return errors


## Whether this species swims (otherwise it walks along the bottom).
func can_swim() -> bool:
	return swim_enter_depth > 0.0


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
