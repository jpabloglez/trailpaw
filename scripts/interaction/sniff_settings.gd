class_name SniffSettings
extends Resource
## What sniffing reveals and for how long. Values live in [code]data/interaction/sniff.tres[/code].

## Resources within this distance are highlighted.
@export_range(1.0, 100.0, 0.5, "suffix:m") var radius: float = 0.0
## At most this many (the nearest).
@export_range(1, 64) var max_highlights: int = 1
## Seconds a highlight stays, fading out over the last [member fade] seconds.
@export_range(0.1, 30.0, 0.1, "suffix:s") var duration: float = 0.0
## Fade-out time at the end of [member duration].
@export_range(0.0, 10.0, 0.05, "suffix:s") var fade: float = 0.0
## Seconds before the next sniff.
@export_range(0.0, 30.0, 0.1, "suffix:s") var cooldown: float = 0.0
## Height of a sparkle above its resource.
@export_range(0.0, 3.0, 0.05, "suffix:m") var lift: float = 0.0
## Sparkle size up close.
@export_range(0.05, 3.0, 0.05, "suffix:m") var size: float = 0.0
## Beyond this distance sparkles grow with it, so far ones stay as legible as near ones.
@export_range(1.0, 100.0, 0.5, "suffix:m") var grow_distance: float = 1.0
## Colour of food sparkles.
@export var food_color: Color = Color.WHITE
## Colour of the water sparkle.
@export var water_color: Color = Color.WHITE
## Directions and rings sampled when looking for the nearest water.
@export_range(4, 64) var water_directions: int = 4
## Rings (evenly spaced up to [member radius]) sampled per direction.
@export_range(1, 32) var water_rings: int = 1
@export_group("Water scent")
## Beyond [member radius], water is scented this far away and shown as a trail ([WaterScent]).
@export_range(0.0, 5000.0, 10.0, "suffix:m") var scent_radius: float = 0.0
## Distance between scent rings and samples.
@export_range(1.0, 100.0, 1.0, "suffix:m") var scent_step: float = 16.0
## Minimum depth of scented water (no puddles).
@export_range(0.0, 5.0, 0.05, "suffix:m") var scent_min_depth: float = 0.3
## Sparkles in the trail towards scented water.
@export_range(1, 16) var trail_count: int = 1
## Metres between trail sparkles.
@export_range(0.5, 20.0, 0.5, "suffix:m") var trail_spacing: float = 3.0
## Seconds between one trail sparkle appearing and the next.
@export_range(0.0, 2.0, 0.05, "suffix:s") var trail_stagger: float = 0.0
