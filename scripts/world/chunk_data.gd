class_name ChunkData
extends RefCounted
## Plain geometry and collision data for one terrain chunk, produced off the main thread
## by [ChunkGenerator] and consumed on the main thread by [code]TerrainChunk[/code].
##
## Vertex positions are local to the chunk's corner on XZ; Y is the absolute height.
## Grid arrays are row-major: index = [code]z * resolution + x[/code].

## Chunk grid coordinate (absolute, never floating-origin local).
var coord: Vector2i
## LOD level this data was generated at (0 = finest).
var lod: int = 0
## Vertices per side of the surface grid.
var resolution: int = 0
## Distance between neighbouring grid vertices (m).
var step: float = 0.0
## Mesh vertex positions.
var vertices := PackedVector3Array()
## Per-vertex normals, derived from the height field (consistent across chunk borders).
var normals := PackedVector3Array()
## Per-vertex UVs in [0, 1] across the chunk.
var uvs := PackedVector2Array()
## Triangle indices (clockwise = front-facing in Godot).
var indices := PackedInt32Array()
## Closed outline of the chunk surface border (local positions), for debug gizmos.
var border := PackedVector3Array()
## Heights for a [HeightMapShape3D] ([code]resolution²[/code], row-major). Empty when the
## chunk gets no collision.
var collision_heights := PackedFloat32Array()


## Number of vertices of the surface grid (excluding any skirt).
func surface_vertex_count() -> int:
	return resolution * resolution


## SHA-256 over all generated arrays: equal data gives an equal hash.
func content_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([coord, lod, resolution, step]))
	ctx.update(vertices.to_byte_array())
	ctx.update(normals.to_byte_array())
	ctx.update(uvs.to_byte_array())
	ctx.update(indices.to_byte_array())
	ctx.update(collision_heights.to_byte_array())
	return ctx.finish().hex_encode()
