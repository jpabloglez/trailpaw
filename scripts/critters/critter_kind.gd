class_name CritterKind
extends Resource
## One kind of small animal of the critter layer ([CritterSystem]): where it lives, how many,
## how it moves and how it flees. Values live in [code]data/critters/<id>.tres[/code].

## Unique id.
@export var id: StringName = &""
## Mesh built in code ([method ProceduralMeshes.critter]).
@export var shape: StringName = &""
## How it moves: [code]&"hopper"[/code] (on dry ground, in hops), [code]&"swimmer"[/code] (on
## the water surface, gliding; never leaves the water) or [code]&"amphibian"[/code] (on the
## banks; dives into the water when scared and comes back up on a nearby bank).
@export var behaviour: StringName = &"hopper"
## Amphibians live on ground up to this high above the water (m).
@export_range(0.0, 5.0, 0.05, "suffix:m") var bank_height: float = 0.8
## Amphibians stay under water this long after diving (min, max, s).
@export var dive_seconds: Vector2 = Vector2(4.0, 8.0)
## Swimmers only use water at least this deep (m).
@export_range(0.0, 5.0, 0.05, "suffix:m") var min_depth: float = 0.4
## Biome id → how many in a chunk that hosts them (min, max).
@export var biome_counts: Dictionary[StringName, Vector2i] = {}
## Chance that a full-detail chunk hosts some.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.0
## Random size range (× the mesh).
@export var scale_range: Vector2 = Vector2(0.9, 1.1)
## Spread of a chunk's group around a random point in the chunk (m).
@export_range(0.0, 64.0, 0.5, "suffix:m") var group_spread: float = 6.0

@export_group("Moving")
## They graze within this distance of their home (m).
@export_range(0.5, 50.0, 0.5, "suffix:m") var home_radius: float = 4.0
## Seconds between hops while calm (min, max).
@export var idle_seconds: Vector2 = Vector2(1.0, 4.0)
## A calm hop: length and height (m), and duration (s).
@export var graze_hop: Vector3 = Vector3(0.4, 0.08, 0.25)
## A fleeing hop: length and height (m), and duration (s).
@export var flee_hop: Vector3 = Vector3(1.4, 0.25, 0.28)
## Fleeing hops zig-zag by up to this angle (degrees).
@export_range(0.0, 90.0, 1.0, "suffix:°") var zigzag: float = 35.0
## Highest slope they hop onto (degrees, from the height function).
@export_range(0.0, 89.0, 1.0, "suffix:°") var max_slope: float = 35.0

@export_group("Fleeing")
## The fox closer than this, and closing faster than [member flee_trigger_speed], scares them.
@export_range(0.0, 50.0, 0.5, "suffix:m") var flee_radius: float = 7.0
## Closing speed that scares them (m/s; the fox walks at ≈ 1.1, trots at 4).
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var flee_trigger_speed: float = 2.0
## Closer than this they flee whatever the speed (m).
@export_range(0.0, 10.0, 0.1, "suffix:m") var startle_radius: float = 1.5
## They keep fleeing at least this long, then calm down where they are (s).
@export_range(0.5, 30.0, 0.5, "suffix:s") var calm_seconds: float = 6.0
