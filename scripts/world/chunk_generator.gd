class_name ChunkGenerator
extends RefCounted
## Builds [ChunkData] for a terrain chunk. Pure and thread-safe: call it from
## [WorkerThreadPool] with a [TerrainSettings] copy owned by the task.
##
## Seam-free by construction: sample positions come from the [b]integer[/b] global grid
## index ([code]coord * (resolution - 1) + i[/code]), so neighbouring chunks evaluate the
## exact same absolute coordinates on their shared border. Normals use central differences
## over a one-sample apron around the chunk, so border normals match too.
## [br][br]
## Budget (worker thread): ~(resolution + 2)² height samples plus one pass to build arrays;
## measured LOD0 65×65 ≈ 6.3 ms, LOD1 17×17 ≈ 0.5 ms (GDScript). Never touches the scene tree.


## Generates the chunk at [param coord] for [param lod]. Collision heights are only
## produced for LOD 0.
static func generate(
	coord: Vector2i, lod: int, settings: TerrainSettings, world_seed: int
) -> ChunkData:
	var sampler := HeightSampler.new(settings, world_seed)
	var res := settings.resolution_for_lod(lod)
	var step := settings.step_for_lod(lod)
	var heights := sample_apron(sampler, coord, res, step)

	var data := ChunkData.new()
	data.coord = coord
	data.lod = lod
	data.resolution = res
	data.step = step
	_build_surface(data, heights)
	if lod == 0:
		data.collision_heights = _interior(heights, res)
	return data


## Heights on a (res + 2)² grid: the chunk's res² vertices plus a one-sample apron.
static func sample_apron(
	sampler: HeightSampler, coord: Vector2i, res: int, step: float
) -> PackedFloat32Array:
	var side := res + 2
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	var base_x := coord.x * (res - 1) - 1
	var base_z := coord.y * (res - 1) - 1
	for j in side:
		var z := float(base_z + j) * step
		for i in side:
			heights[j * side + i] = sampler.height_at(float(base_x + i) * step, z)
	return heights


static func _build_surface(data: ChunkData, heights: PackedFloat32Array) -> void:
	var res := data.resolution
	var step := data.step
	var side := res + 2
	var inv := 1.0 / float(res - 1)
	data.vertices.resize(res * res)
	data.normals.resize(res * res)
	data.uvs.resize(res * res)
	for j in res:
		for i in res:
			var a := (j + 1) * side + (i + 1)
			var v := j * res + i
			data.vertices[v] = Vector3(i * step, heights[a], j * step)
			var dx := heights[a + 1] - heights[a - 1]
			var dz := heights[a + side] - heights[a - side]
			data.normals[v] = Vector3(-dx, 2.0 * step, -dz).normalized()
			data.uvs[v] = Vector2(i * inv, j * inv)
	data.indices.resize((res - 1) * (res - 1) * 6)
	var k := 0
	for j in res - 1:
		for i in res - 1:
			var v00 := j * res + i
			var v10 := v00 + 1
			var v01 := v00 + res
			var v11 := v01 + 1
			# Alternate the diagonal to avoid a directional bias in the triangulation.
			if (i + j) % 2 == 0:
				_put_quad(data.indices, k, v00, v10, v11, v01)
			else:
				_put_quad(data.indices, k, v10, v11, v01, v00)
			k += 6


## Writes two clockwise triangles for the quad a-b-c-d (a→b→c, a→c→d).
static func _put_quad(indices: PackedInt32Array, k: int, a: int, b: int, c: int, d: int) -> void:
	indices[k] = a
	indices[k + 1] = b
	indices[k + 2] = c
	indices[k + 3] = a
	indices[k + 4] = c
	indices[k + 5] = d


static func _interior(heights: PackedFloat32Array, res: int) -> PackedFloat32Array:
	var side := res + 2
	var out := PackedFloat32Array()
	out.resize(res * res)
	for j in res:
		for i in res:
			out[j * res + i] = heights[(j + 1) * side + (i + 1)]
	return out
