class_name SoarerSettings
extends Resource
## Big birds that soar in wide circles high over the land ([Soarers]; the golden eagle of the
## mountains, Phase 17). Values live in [code]data/critters/eagle.tres[/code].

## Biomes they soar over (their circles stay above these).
@export var biomes: Array[StringName] = []
## Most of them in the sky at once.
@export_range(1, 8) var max_soarers: int = 2
## Chance per second that one appears while the fox is over their biomes by day.
@export_range(0.0, 1.0, 0.005) var appear_chance: float = 0.05
## Their circle's centre appears this far from the fox (min, max, m).
@export var appear_distance: Vector2 = Vector2(60.0, 160.0)
## They leave beyond this distance from the fox (m).
@export_range(50.0, 2000.0, 10.0, "suffix:m") var leave_distance: float = 450.0
## Radius of the circles (min, max, m) and height above the ground under them (min, max, m).
@export var circle_radius: Vector2 = Vector2(35.0, 70.0)
@export var soar_height: Vector2 = Vector2(45.0, 70.0)
## Gliding speed along the circle (m/s) and how fast the circle drifts (m/s).
@export_range(1.0, 40.0, 0.5, "suffix:m/s") var speed: float = 9.0
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var drift: float = 1.2
## How far they bank into the turn (degrees).
@export_range(0.0, 60.0, 1.0, "suffix:°") var bank_degrees: float = 18.0
## Size (× the songbird mesh) and plumage colour.
@export_range(1.0, 20.0, 0.1) var scale: float = 7.0
@export var tint: Color = Color(0.3, 0.21, 0.12)
## Seconds between cries (min, max), heard within [member cry_radius] of the fox.
@export var cry_seconds: Vector2 = Vector2(12.0, 35.0)
@export_range(10.0, 1000.0, 10.0, "suffix:m") var cry_radius: float = 250.0
