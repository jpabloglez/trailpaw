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
## Per-vertex ground palette: rgb = colour A, alpha = blue channel of colour B.
var colors := PackedColorArray()
## Per-vertex red/green channels of ground palette colour B (uploaded as UV2). Colour B is
## packed into standard attributes so every renderer (incl. Compatibility) reads it.
var uv2 := PackedVector2Array()
## Triangle indices (clockwise = front-facing in Godot).
var indices := PackedInt32Array()
## Lowest surface height in the chunk (m, absolute).
var min_height: float = INF
## Water surface height copied from the settings (m, absolute).
var water_level: float = 0.0
## Closed outline of the chunk surface border (local positions), for debug gizmos.
var border := PackedVector3Array()
## Vegetation instances: type id → [PackedFloat32Array] in [member MultiMesh.buffer]
## layout (12 floats per instance, local to the chunk corner). See [VegetationScatterer].
var vegetation: Dictionary = {}
## Heights for a [HeightMapShape3D] ([code]resolution²[/code], row-major). Empty when the
## chunk gets no collision.
var collision_heights := PackedFloat32Array()


## Whether any ground in this chunk lies below the water surface.
func has_water() -> bool:
	return min_height < water_level


## Number of vegetation instances of type [param id].
func vegetation_count(id: StringName) -> int:
	var buffer: PackedFloat32Array = vegetation.get(id, PackedFloat32Array())
	return buffer.size() / VegetationScatterer.FLOATS_PER_INSTANCE


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
	ctx.update(colors.to_byte_array())
	ctx.update(uv2.to_byte_array())
	ctx.update(indices.to_byte_array())
	ctx.update(collision_heights.to_byte_array())
	var ids := vegetation.keys()
	ids.sort()
	for id: StringName in ids:
		ctx.update(String(id).to_utf8_buffer())
		ctx.update((vegetation[id] as PackedFloat32Array).to_byte_array())
	return ctx.finish().hex_encode()
