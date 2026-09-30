class_name FaunaSettings
extends Resource
## Population and AI LOD of the [FaunaDirector]. Values live in
## [code]data/fauna/director.tres[/code].

## Most animals alive at once around the player.
@export_range(0, 64) var max_agents: int = 0
## Animals never appear closer than this to the player (m).
@export_range(0.0, 200.0, 1.0, "suffix:m") var min_spawn_distance: float = 0.0
## Animals further than this from the player are removed (m).
@export_range(10.0, 500.0, 1.0, "suffix:m") var despawn_distance: float = 0.0
## Within this distance agents run at full rate (m).
@export_range(1.0, 200.0, 1.0, "suffix:m") var full_radius: float = 0.0
## Within this distance (beyond [member full_radius]) agents think at [member mid_hz]; beyond
## it they are frozen (m).
@export_range(1.0, 400.0, 1.0, "suffix:m") var mid_radius: float = 0.0
## Brain rate at full detail.
@export_range(0.1, 30.0, 0.1, "suffix:Hz") var full_hz: float = 5.0
## Brain rate at mid distance.
@export_range(0.1, 30.0, 0.1, "suffix:Hz") var mid_hz: float = 2.0
## Physics ticks per behaviour tick at mid distance (movement in bigger steps).
@export_range(1, 10) var mid_stride: int = 3
## Radius around a chunk's centre where its herd is placed (m).
@export_range(1.0, 64.0, 0.5, "suffix:m") var herd_spread: float = 0.0
## Steepest ground an animal may appear on.
@export_range(1.0, 89.0, 0.5, "suffix:°") var max_spawn_slope: float = 0.0
## Spawns started per frame at most (each instances a model).
@export_range(1, 8) var spawns_per_frame: int = 1


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if max_agents <= 0:
		errors.append("max_agents must be > 0")
	if not (full_radius < mid_radius and mid_radius < despawn_distance):
		errors.append("radii must satisfy full_radius < mid_radius < despawn_distance")
	if min_spawn_distance >= despawn_distance:
		errors.append("min_spawn_distance must be < despawn_distance")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
