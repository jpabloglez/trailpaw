class_name QualityPreset
extends Resource
## A graphics quality level (ARCHITECTURE §10). Phase 4 uses the vegetation density; later
## phases add shadows, load radius and render scale. Values live in [code]data/quality/[/code].

## Stable identifier ([code]&"low"[/code], [code]&"medium"[/code], [code]&"high"[/code]).
@export var id: StringName = &""
## Name shown in the settings menu (Phase 10).
@export var display_name: String = ""
## Multiplier for every vegetation density.
@export_range(0.0, 2.0, 0.05) var vegetation_density: float = 0.0
## Dust puffs and water splashes ([MotionEffects]).
@export var motion_effects: bool = true


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if vegetation_density <= 0.0:
		errors.append("vegetation_density must be > 0")
	return errors
