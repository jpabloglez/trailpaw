## Session-wide game state: world seed, distance travelled, current biome, elapsed time
## and pause state.
##
## Fields are added by the phase that needs them (see [code]docs/ARCHITECTURE.md[/code] §2).
## [br][br]
## Autoload name: [code]GameState[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node

## Seed for all procedural world generation. Set before the world starts streaming.
var world_seed: int = 0
## Chunk-grid offset of the floating origin: local position (0, 0, 0) is the corner of this
## chunk. Integer, so absolute positions stay exact however far the player travels.
var origin_chunk: Vector2i = Vector2i.ZERO
## Chunk size (m) used to convert [member origin_chunk] to metres. Set by
## [code]FloatingOrigin.configure()[/code].
var chunk_size: float = 0.0

## Biome the player is currently in (as last announced by the biome tracker).
var current_biome: StringName = &""


## World-space offset of the local origin (m).
func origin_offset() -> Vector3:
	return Vector3(origin_chunk.x, 0.0, origin_chunk.y) * chunk_size


## Absolute world position of a local (scene) position. Use this, never the local position,
## for anything distance-driven (biomes, saves). Exact origin + local offset in 64-bit
## script floats; the returned [Vector3] has single precision (≈ 1 mm at 10 km).
func absolute_position(local: Vector3) -> Vector3:
	return local + origin_offset()


## Local (scene) position of an absolute world position.
func local_position(absolute: Vector3) -> Vector3:
	return absolute - origin_offset()
