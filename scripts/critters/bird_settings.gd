class_name BirdSettings
extends Resource
## Songbird flocks ([BirdFlocks]): where and how many, how they perch, fly and scatter, and how
## much birdsong they make. Values live in [code]data/critters/birds.tres[/code].

## Biome id → chance that a full-detail chunk hosts a flock.
@export var biome_chance: Dictionary[StringName, float] = {}
## Birds in a flock (min, max).
@export var flock_size: Vector2i = Vector2i(4, 9)
## Most birds alive at once.
@export_range(1, 256) var max_birds: int = 60
## Plumage colours (one per flock).
@export var palette: Array[Color] = []

@export_group("Perching and flying")
## Seconds a flock stays perched before moving on (min, max), by day.
@export var perch_seconds: Vector2 = Vector2(12.0, 35.0)
## Distance of a calm move to another perch (min, max, m).
@export var move_distance: Vector2 = Vector2(15.0, 40.0)
## Distance a scared flock flies away (min, max, m).
@export var flee_distance: Vector2 = Vector2(30.0, 50.0)
## Flight speed (m/s).
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var flight_speed: float = 7.0
## Extra height of the flight arc (m).
@export_range(0.0, 30.0, 0.5, "suffix:m") var arc_height: float = 6.0
## Birds spread over a crown (m) or a patch of ground (m).
@export_range(0.0, 5.0, 0.05, "suffix:m") var crown_spread: float = 0.8
@export_range(0.0, 10.0, 0.1, "suffix:m") var ground_spread: float = 2.5

@export_group("Scaring")
## The fox within this distance…
@export_range(0.0, 50.0, 0.5, "suffix:m") var scare_radius: float = 7.0
## …moving faster than this (m/s) or jumping scares the whole flock.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var scare_speed: float = 2.5

@export_group("Birdsong")
## Perched birds within this distance sing (m)…
@export_range(1.0, 200.0, 1.0, "suffix:m") var song_radius: float = 40.0
## …and this many of them make the full birdsong level.
@export_range(1, 64) var song_full_count: int = 6
