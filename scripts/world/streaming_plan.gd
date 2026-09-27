class_name StreamingPlan
extends RefCounted
## Pure chunk-streaming decisions: which chunks should exist around a centre chunk, in what
## order to load them and when to drop them. No nodes, no threads: fully unit-testable.
##
## Budget: [method desired_chunks] is O(load_radius²) and only runs when the target
## crosses into another chunk, never every frame.

## How strongly the view direction pulls a chunk forward in the queue, in chunks of
## distance. Below 1 so it only reorders chunks at similar distances.
const VIEW_BIAS: float = 0.35
## Extra distance (chunks) a LOD 0 chunk may drift before it is downgraded again.
const LOD_HYSTERESIS: float = 1.0
## Coarse LOD used outside the LOD 0 radius.
const FAR_LOD: int = 1


## Chunk grid coordinate containing absolute position ([param x], [param z]).
static func chunk_at(x: float, z: float, chunk_size: float) -> Vector2i:
	return Vector2i(floori(x / chunk_size), floori(z / chunk_size))


## Distance between two chunk coordinates, in chunks.
static func chunk_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()


## Chunks that should be loaded around [param center], mapped to their LOD level.
## [param current_lods] (loaded coord → LOD) enables LOD hysteresis.
static func desired_chunks(
	center: Vector2i, settings: StreamingSettings, current_lods: Dictionary = {}
) -> Dictionary[Vector2i, int]:
	var desired: Dictionary[Vector2i, int] = {}
	var r := settings.load_radius
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var coord := center + Vector2i(dx, dz)
			var distance := chunk_distance(coord, center)
			if distance <= float(r):
				desired[coord] = lod_for(distance, current_lods.get(coord, -1), settings)
	return desired


## LOD for a chunk at [param distance] chunks. A chunk already at LOD 0 keeps it until it
## is [constant LOD_HYSTERESIS] beyond the LOD 0 radius.
static func lod_for(distance: float, current_lod: int, settings: StreamingSettings) -> int:
	if distance <= settings.lod0_radius:
		return 0
	if current_lod == 0 and distance <= settings.lod0_radius + LOD_HYSTERESIS:
		return 0
	return FAR_LOD


## Whether a loaded chunk is far enough from [param center] to be dropped.
static func should_unload(coord: Vector2i, center: Vector2i, settings: StreamingSettings) -> bool:
	return chunk_distance(coord, center) > float(settings.unload_radius)


## Load priority: lower loads first. Nearest first; chunks ahead of [param view_dir]
## (normalised XZ direction) win ties.
static func load_priority(coord: Vector2i, center: Vector2i, view_dir: Vector2) -> float:
	var offset := Vector2(coord - center)
	var distance := offset.length()
	if distance == 0.0:
		return -VIEW_BIAS
	return distance - VIEW_BIAS * offset.dot(view_dir) / distance


## Sorts [param coords] in place by [method load_priority].
static func sort_by_priority(coords: Array[Vector2i], center: Vector2i, view_dir: Vector2) -> void:
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return load_priority(a, center, view_dir) < load_priority(b, center, view_dir)
	)
