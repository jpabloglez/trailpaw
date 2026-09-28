class_name VegetationScatterer
extends RefCounted
## Scatters vegetation over one chunk's surface. Built once on the main thread from the biome
## table (an immutable snapshot of plain arrays) and then only read, so worker tasks can share
## it; per-chunk state lives in locals and the task's own [HeightSampler] resolver.
##
## Per type: a jittered grid sized for the type's densest biome; each candidate is kept with
## probability Σ(biome weight × biome density that passes its slope/height rules) / max
## density, modulated by a clumping noise. Heights and slopes come from the exact triangle of
## the chunk mesh under the point, so instances sit on the visible surface at every LOD.
## Placement is deterministic per (world seed, chunk, type) and independent of the LOD.
## [br][br]
## Output: [member ChunkData.vegetation] maps type id → [PackedFloat32Array] in
## [member MultiMesh.buffer] layout (12 floats per instance, local to the chunk corner).
## [br][br]
## Budget (worker thread): O(candidates) with one biome lookup per candidate in chunks that
## straddle a band boundary (constant otherwise).

## Floats per instance in [member MultiMesh.buffer] (Transform3D).
const FLOATS_PER_INSTANCE: int = 12
## Seed salt for the clumping noise.
const CLUSTER_SALT: int = 0xC1A5

var _type_ids: Array[StringName] = []
var _scale_min := PackedFloat32Array()
var _scale_max := PackedFloat32Array()
var _align := PackedFloat32Array()
var _near_only: Array[bool] = []
var _max_density := PackedFloat32Array()
## Per biome (index), per type (index): entry parameters (density 0 = does not grow there).
var _density: Array[PackedFloat32Array] = []
var _max_slope_cos: Array[PackedFloat32Array] = []
var _min_height: Array[PackedFloat32Array] = []
var _max_height: Array[PackedFloat32Array] = []
var _cluster: Array[PackedFloat32Array] = []
var _biome_index: Dictionary = {}
var _cluster_frequency: float = 0.035


func _init(table: BiomeTable) -> void:
	var type_index := {}
	for biome in table.biomes:
		for entry in biome.vegetation:
			if not type_index.has(entry.type.id):
				type_index[entry.type.id] = _type_ids.size()
				_type_ids.append(entry.type.id)
				_scale_min.append(entry.type.scale_min)
				_scale_max.append(entry.type.scale_max)
				_align.append(entry.type.align_to_ground)
				_near_only.append(entry.type.near_only)
				_max_density.append(0.0)
	var n := _type_ids.size()
	for b in table.biomes.size():
		var biome := table.biomes[b]
		_biome_index[biome] = b
		var density := PackedFloat32Array()
		var slope := PackedFloat32Array()
		var lo := PackedFloat32Array()
		var hi := PackedFloat32Array()
		var cluster := PackedFloat32Array()
		for arr: PackedFloat32Array in [density, slope, lo, hi, cluster]:
			arr.resize(n)
		for entry in biome.vegetation:
			var t: int = type_index[entry.type.id]
			density[t] = entry.density
			slope[t] = cos(deg_to_rad(entry.max_slope_degrees))
			lo[t] = entry.min_height
			hi[t] = entry.max_height
			cluster[t] = entry.cluster
			_max_density[t] = maxf(_max_density[t], entry.density)
		_density.append(density)
		_max_slope_cos.append(slope)
		_min_height.append(lo)
		_max_height.append(hi)
		_cluster.append(cluster)


## Vegetation type ids in stable order.
func type_ids() -> Array[StringName]:
	return _type_ids


## Scatters over [param data] (surface already built) and stores the result in
## [member ChunkData.vegetation]. [param density_scale] multiplies every density (quality).
func scatter(
	data: ChunkData,
	sampler: HeightSampler,
	world_seed: int,
	water_level: float,
	density_scale: float = 1.0
) -> void:
	data.vegetation = {}
	var resolver := sampler.resolver()
	if resolver == null or density_scale <= 0.0:
		return
	var size := data.step * float(data.resolution - 1)
	var origin := Vector2(data.coord) * size
	var blend := BiomeBlend.new()
	var uniform := resolver.uniform_blend(
		origin.x + size * 0.5, origin.y + size * 0.5, size * 0.75, blend
	)
	var cluster_noise := FastNoiseLite.new()
	cluster_noise.seed = HeightSampler.layer_seed(world_seed, CLUSTER_SALT)
	cluster_noise.frequency = _cluster_frequency
	var rng := RandomNumberGenerator.new()
	for t in _type_ids.size():
		if _near_only[t] and data.lod != 0:
			continue
		var max_density := _max_density[t] * density_scale
		var spacing := sqrt(100.0 / max_density)
		var cells := maxi(1, floori(size / spacing))
		var cell := size / cells
		rng.seed = _chunk_type_seed(world_seed, data.coord, t)
		var out := PackedFloat32Array()
		for cz in cells:
			for cx in cells:
				var lx := (cx + rng.randf()) * cell
				var lz := (cz + rng.randf()) * cell
				var roll := rng.randf()
				var yaw := rng.randf() * TAU
				var scale_roll := rng.randf()
				var ax := origin.x + lx
				var az := origin.y + lz
				if not uniform:
					resolver.blend_into(ax, az, blend)
				var surface := surface_at(data, lx, lz)
				var height: float = surface[0] - water_level
				var normal: Vector3 = surface[1]
				var clump := cluster_noise.get_noise_2d(ax, az) * 0.5 + 0.5
				var chance := _acceptance(t, blend, height, normal.y, clump) / _max_density[t]
				if roll >= chance:
					continue
				var s := lerpf(_scale_min[t], _scale_max[t], scale_roll)
				_append_transform(out, Vector3(lx, surface[0], lz), normal, _align[t], yaw, s)
		if not out.is_empty():
			data.vegetation[_type_ids[t]] = out


## Density (per 100 m²) of type [param t] accepted at a point: the blend of the two biomes'
## densities, each only where its slope/height rules pass, shaped by clumping.
func _acceptance(t: int, blend: BiomeBlend, height: float, normal_y: float, clump: float) -> float:
	var total := _biome_density(t, _biome_index[blend.primary], height, normal_y, clump)
	total *= 1.0 - blend.secondary_weight
	if blend.secondary != null:
		var b: int = _biome_index[blend.secondary]
		total += _biome_density(t, b, height, normal_y, clump) * blend.secondary_weight
	return total


func _biome_density(t: int, b: int, height: float, normal_y: float, clump: float) -> float:
	var density := _density[b][t]
	if density <= 0.0 or height < _min_height[b][t] or height > _max_height[b][t]:
		return 0.0
	if normal_y < _max_slope_cos[b][t]:
		return 0.0
	var c := _cluster[b][t]
	return density * clampf(1.0 - c + c * 2.0 * clump, 0.0, 2.0)


## Height (absolute) and face normal of the chunk mesh at local ([param lx], [param lz]),
## using the same alternating diagonals as [ChunkGenerator]. Returns [height, normal].
static func surface_at(data: ChunkData, lx: float, lz: float) -> Array:
	var res := data.resolution
	var fx := clampf(lx / data.step, 0.0, float(res - 1) - 1e-4)
	var fz := clampf(lz / data.step, 0.0, float(res - 1) - 1e-4)
	var i := floori(fx)
	var j := floori(fz)
	var u := fx - i
	var v := fz - j
	var v00 := data.vertices[j * res + i]
	var v10 := data.vertices[j * res + i + 1]
	var v01 := data.vertices[(j + 1) * res + i]
	var v11 := data.vertices[(j + 1) * res + i + 1]
	var a: Vector3
	var b: Vector3
	var c: Vector3
	if (i + j) % 2 == 0:
		# Diagonal v00–v11: triangles (v00, v10, v11) and (v00, v11, v01).
		if u >= v:
			a = v00
			b = v10
			c = v11
		else:
			a = v00
			b = v11
			c = v01
	else:
		# Diagonal v10–v01: triangles (v10, v11, v01) and (v10, v01, v00).
		if u + v >= 1.0:
			a = v10
			b = v11
			c = v01
		else:
			a = v10
			b = v01
			c = v00
	var plane := Plane(a, b, c)
	var point := Vector3(lx, 0.0, lz)
	var height := (plane.d - plane.normal.x * point.x - plane.normal.z * point.z) / plane.normal.y
	return [height, plane.normal]


static func _append_transform(
	out: PackedFloat32Array, origin: Vector3, normal: Vector3, align: float, yaw: float, s: float
) -> void:
	var up := Vector3.UP.slerp(normal, align).normalized()
	var basis := Basis(Vector3.UP, yaw)
	if not up.is_equal_approx(Vector3.UP):
		var axis := Vector3.UP.cross(up).normalized()
		basis = Basis(axis, Vector3.UP.angle_to(up)) * basis
	basis = basis.scaled(Vector3.ONE * s)
	# MultiMesh.buffer layout: row-major 3×4 (basis rows, then origin component).
	(
		out
		. append_array(
			[
				basis.x.x,
				basis.y.x,
				basis.z.x,
				origin.x,
				basis.x.y,
				basis.y.y,
				basis.z.y,
				origin.y,
				basis.x.z,
				basis.y.z,
				basis.z.z,
				origin.z,
			]
		)
	)


static func _chunk_type_seed(world_seed: int, coord: Vector2i, type_index: int) -> int:
	var chunk_seed := HeightSampler.layer_seed(world_seed, coord.x * 73856093 ^ coord.y * 19349663)
	return HeightSampler.layer_seed(chunk_seed, type_index + 1)
