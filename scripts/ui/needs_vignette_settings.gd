class_name NeedsVignetteSettings
extends Resource
## Look and timing of the critical-needs vignette. Values live in
## [code]data/ui/needs_vignette.tres[/code].

## Edge colour.
@export var tint: Color = Color.BLACK
## Edge opacity at full intensity.
@export_range(0.0, 1.0, 0.01) var max_alpha: float = 0.0
## Intensity added by each critical need (capped at 1).
@export_range(0.0, 1.0, 0.01) var intensity_per_need: float = 0.0
## Intensity change per second (eases in and out).
@export_range(0.01, 10.0, 0.01, "suffix:1/s") var fade_per_second: float = 0.0
## Radius where the tint starts, on an ellipse fitted to the screen (0 = centre, 1 = edge
## midpoints, ~1.41 = corners).
@export_range(0.0, 2.0, 0.01) var inner_radius: float = 0.0
## Normalised radius where the tint reaches full strength.
@export_range(0.0, 2.0, 0.01) var outer_radius: float = 0.0
## Frosty edge colour while the animal is too cold, and its intensity (Phase 17).
@export var cold_tint: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var cold_intensity: float = 0.0


## Target intensity for [param critical_count] critical needs.
func target_intensity(critical_count: int) -> float:
	return minf(1.0, critical_count * intensity_per_need)
