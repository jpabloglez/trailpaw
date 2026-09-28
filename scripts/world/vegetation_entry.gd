class_name VegetationEntry
extends Resource
## Where and how often a [VegetationType] grows in one biome ([member
## BiomeDefinition.vegetation]). Heights are relative to the water level, so shore plants and
## "never underwater" rules survive sea-level tuning.

## What grows.
@export var type: VegetationType
## Average instances per 100 m² (a 10 × 10 m patch) where all the rules pass.
@export_range(0.0, 200.0, 0.01) var density: float = 0.0
## Steepest ground it grows on.
@export_range(0.0, 89.0, 0.5, "suffix:°") var max_slope_degrees: float = 0.0
## Lowest ground height relative to the water level (>= 0: never underwater).
@export_range(0.0, 100.0, 0.1, "suffix:m") var min_height: float = 0.0
## Highest ground height relative to the water level.
@export_range(0.0, 200.0, 0.1, "suffix:m") var max_height: float = 0.0
## Clumping (0 = even spread, 1 = strong patches with bare ground between).
@export_range(0.0, 1.0, 0.05) var cluster: float = 0.0


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if type == null:
		errors.append("type must be set")
	else:
		for problem: String in type.get_validation_errors():
			errors.append("type %s: %s" % [type.id, problem])
	if density <= 0.0:
		errors.append("density must be > 0")
	if max_slope_degrees <= 0.0:
		errors.append("max_slope_degrees must be > 0")
	if min_height < 0.0:
		errors.append("min_height must be >= 0 (vegetation never grows underwater)")
	if max_height <= min_height:
		errors.append("max_height must be > min_height")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
