class_name FlitterKind
extends Resource
## One kind of small flier for [Flitters]: butterflies visiting flowers, dragonflies darting over
## the water plants. Values live in [code]data/critters/*.tres[/code].

## Identifier (debug lines).
@export var id: StringName = &""
## Chunk spots they visit ([method TerrainChunk.spots]): [code]&"flower"[/code] or
## [code]&"water_plant"[/code].
@export var spots: StringName = &"flower"
## Biomes where they are out.
@export var biomes: Array[StringName] = []
## Out by day (true) or at night.
@export var by_day: bool = true

@export_group("Numbers")
## Most of them around the player.
@export_range(0, 64) var max_count: int = 14
## One flier per this many spots nearby.
@export_range(1, 50) var spots_per_flier: int = 6
## Spots this close to the player get visitors; farther fliers leave (m).
@export_range(5.0, 100.0, 1.0, "suffix:m") var radius: float = 22.0

@export_group("Flight")
## Height they hover at above their spot (m), and how much it wobbles.
@export_range(0.0, 5.0, 0.05, "suffix:m") var hover_height: float = 0.75
@export_range(0.0, 2.0, 0.05, "suffix:m") var hover_wobble: float = 0.25
## Radius of the loop they fly around their spot (m), and how fast they go round it.
@export_range(0.0, 5.0, 0.05, "suffix:m") var loop_radius: float = 0.6
@export_range(0.0, 5.0, 0.05) var loop_rate: float = 1.3
## Darting instead of looping: hover still, then dash to a new point around the spot.
@export var darts: bool = false
## Seconds a darting flier hovers between dashes (min, max).
@export var hover_seconds: Vector2 = Vector2(0.6, 1.6)
## Flying and scattering speeds (m/s).
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var flit_speed: float = 1.1
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var scatter_speed: float = 3.5
## Seconds, on average, before moving on to another spot.
@export_range(1.0, 120.0, 0.5, "suffix:s") var stay_seconds: float = 20.0
## The fox within this distance moving faster than [member scare_speed] scatters them.
@export_range(0.0, 20.0, 0.1, "suffix:m") var scare_radius: float = 2.5
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var scare_speed: float = 2.5

@export_group("Looks")
## Mesh: [code]&"butterfly"[/code] or [code]&"dragonfly"[/code] ([ProceduralMeshes]).
@export var shape: StringName = &"butterfly"
## Drawn this many times bigger than life, so they read from the player's camera.
@export_range(0.5, 5.0, 0.05) var size: float = 1.6
## Wing beat ([code]shaders/bird.gdshader[/code]): rate (rad/s), angle (rad).
@export var flap_rate: float = 30.0
@export var flap_angle: float = 1.25
## Colours (one per flier, at random).
@export var palette: Array[Color] = []
