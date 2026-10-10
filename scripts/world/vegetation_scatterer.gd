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
## Drops ([VegetationDrop]: berries on bushes, apples under oaks) are derived from each parent
## instance with a seed per (world seed, chunk, type, parent index), in LOD 0 chunks only, and
## stored under the drop's id. Drops on the ground outside the chunk or under water are skipped.
## [br][br]
## Budget (worker thread): O(candidates) with one biome lookup per candidate in chunks that
## straddle a band boundary (constant otherwise).

## Floats per instance in [member MultiMesh.buffer] (Transform3D).
const FLOATS_PER_INSTANCE: int = 12
## Seed salt for the clumping noise.
const CLUSTER_SALT: int = 0xC1A5
## Seed salt for derived drops.
const DROP_SALT: int = 0xD70B
## Drops on the ground stay this far above the water surface (m).
const DROP_DRY_MARGIN: float = 0.05

## Rural hamlets (Phase 16): no plant grows on their pieces, and no tall one near their well
## ([method HamletPlan.circles_in]). Optional; set by the [WorldStreamer].
var hamlets: HamletSettings

var _type_ids: Array[StringName] = []
var _scale_min := PackedFloat32Array()
var _scale_max := PackedFloat32Array()
var _align := PackedFloat32Array()
var _near_only: Array[bool] = []
var _floats: Array[bool] = []
var _tall: Array[bool] = []  # trees, bushes, rocks and logs: cleared around a hamlet's well
var _max_density := PackedFloat32Array()
## Per biome (index), per type (index): entry parameters (density 0 = does not grow there).
var _density: Array[PackedFloat32Array] = []
var _max_slope_cos: Array[PackedFloat32Array] = []
var _min_height: Array[PackedFloat32Array] = []
var _max_height: Array[PackedFloat32Array] = []
var _cluster: Array[PackedFloat32Array] = []
var _biome_index: Dictionary = {}
## Per type: drop id (&"" = none) and its parameters
## [count_min, count_max, placement, radius_min, radius_max, height_min, height_max, size].
var _drop_ids: Array[StringName] = []
var _drop_params: Array[PackedFloat32Array] = []
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
				_floats.append(entry.type.float_on_water)
				_tall.append(entry.type.collision_radius > 0.0)
				_max_density.append(0.0)
				_snapshot_drop(entry.type.drop)
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
		origin.x + size * 0.5, origin.y + size * 0.5, size * 0.75, blend, false
	)
	var cluster_noise := FastNoiseLite.new()
	cluster_noise.seed = HeightSampler.layer_seed(world_seed, CLUSTER_SALT)
	cluster_noise.frequency = _cluster_frequency
	var rng := RandomNumberGenerator.new()
	var cleared := PackedVector4Array()  # hamlet clearings touching this chunk (usually none)
	if hamlets != null:
		cleared = HamletPlan.circles_in(
			Rect2(origin, Vector2(size, size)), hamlets, sampler, world_seed, water_level
		)
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
				if not cleared.is_empty() and _in_clearing(cleared, ax, az, _tall[t]):
					continue
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
				if _floats[t]:  # at the water surface, upright
					_append_transform(out, Vector3(lx, water_level, lz), Vector3.UP, 0.0, yaw, s)
				else:
					_append_transform(out, Vector3(lx, surface[0], lz), normal, _align[t], yaw, s)
		if not out.is_empty():
			data.vegetation[_type_ids[t]] = out
			if data.lod == 0 and _drop_ids[t] != &"":
				_derive_drops(data, t, out, world_seed, water_level)


# Whether absolute (x, z) is inside a hamlet clearing that removes this plant: a piece's
# footprint removes everything, the area around the well only [param tall] plants.
static func _in_clearing(cleared: PackedVector4Array, x: float, z: float, tall: bool) -> bool:
	for c in cleared:
		if c.w < 0.5 and not tall:
			continue
		var dx := x - c.x
		var dz := z - c.y
		if dx * dx + dz * dz < c.z * c.z:
			return true
	return false


## Drop id of type [param type_id] (&"" when it has none).
func drop_of(type_id: StringName) -> StringName:
	var t := _type_ids.find(type_id)
	return _drop_ids[t] if t >= 0 else &""


func _snapshot_drop(drop: VegetationDrop) -> void:
	if drop == null:
		_drop_ids.append(&"")
		_drop_params.append(PackedFloat32Array())
		return
	_drop_ids.append(drop.id)
	(
		_drop_params
		. append(
			PackedFloat32Array(
				[
					drop.count_min,
					drop.count_max,
					drop.placement,
					drop.radius_min,
					drop.radius_max,
					drop.height_min,
					drop.height_max,
					drop.size,
				]
			)
		)
	)


## Places the drops of every parent instance of type [param t] (in [param parents]).
func _derive_drops(
	data: ChunkData, t: int, parents: PackedFloat32Array, world_seed: int, water_level: float
) -> void:
	var p := _drop_params[t]
	var on_ground := int(p[2]) == VegetationDrop.Placement.GROUND
	var size := data.step * float(data.resolution - 1)
	var base_seed := HeightSampler.layer_seed(
		_chunk_type_seed(world_seed, data.coord, t), DROP_SALT
	)
	var rng := RandomNumberGenerator.new()
	var out := PackedFloat32Array()
	var stride := FLOATS_PER_INSTANCE
	for parent in parents.size() / stride:
		var o := parent * stride
		rng.seed = HeightSampler.layer_seed(base_seed, parent + 1)
		var count := rng.randi_range(int(p[0]), int(p[1]))
		for d in count:
			var angle := rng.randf() * TAU
			var radius := lerpf(p[3], p[4], rng.randf())
			var height := 0.0 if on_ground else lerpf(p[5], p[6], rng.randf())
			var yaw := rng.randf() * TAU
			# Offset in model units, through the parent's basis (rows of the buffer).
			var v := Vector3(cos(angle) * radius, height, sin(angle) * radius)
			var offset := Vector3(
				parents[o] * v.x + parents[o + 1] * v.y + parents[o + 2] * v.z,
				parents[o + 4] * v.x + parents[o + 5] * v.y + parents[o + 6] * v.z,
				parents[o + 8] * v.x + parents[o + 9] * v.y + parents[o + 10] * v.z
			)
			var pos := Vector3(parents[o + 3], parents[o + 7], parents[o + 11]) + offset
			if on_ground:
				if pos.x < 0.0 or pos.z < 0.0 or pos.x > size or pos.z > size:
					continue
				pos.y = surface_at(data, pos.x, pos.z)[0]
			if pos.y < water_level + DROP_DRY_MARGIN:
				continue
			_append_transform(out, pos, Vector3.UP, 0.0, yaw, p[7])
	if not out.is_empty():
		data.vegetation[_drop_ids[t]] = out


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
