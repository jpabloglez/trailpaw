class_name HamletPlan
extends RefCounted
## Pure, deterministic placement of rural hamlets (ADR-007). The world is split into square
## cells of [member HamletSettings.cell_size]; each cell, seeded per (world seed, cell), may hold
## one hamlet at a flat, dry site fully inside a meadow or the hills, laid out around a well:
## houses on a ring facing it, a stable with a fenced pen, props by the houses.
##
## Terrain heights are not changed: pieces stand on the ground at their centre (sites are flat).
## Vegetation is cleared from footprints (everything) and from the area around the well (trees,
## bushes, rocks and logs) — see [method circles_in].
## [br][br]
## Thread-safe: layouts are computed once per (seed, cell) under a mutex and cached for the
## session; chunk workers and the main thread see the same hamlets. A cell costs ≤ 8 × 81 height
## samples once.

## Salt for hamlet seeds.
const SALT: int = 0x4A3E1

static var _cache: Dictionary = {}  # Vector3i(seed, cell.x, cell.y) → HamletLayout or null
static var _mutex := Mutex.new()


## The hamlet of [param cell], or null (cached).
static func layout(
	cell: Vector2i, settings: HamletSettings, sampler: HeightSampler, world_seed: int, water: float
) -> HamletLayout:
	var key := Vector3i(world_seed, cell.x, cell.y)
	_mutex.lock()
	var found: bool = _cache.has(key)
	var cached: HamletLayout = _cache.get(key)
	_mutex.unlock()
	if found:
		return cached
	var made := _make(cell, settings, sampler, world_seed, water)
	_mutex.lock()
	_cache[key] = made
	_mutex.unlock()
	return made


## Hamlets whose well is within [param radius] of absolute ([param x], [param z]).
static func near(
	x: float,
	z: float,
	radius: float,
	settings: HamletSettings,
	sampler: HeightSampler,
	world_seed: int,
	water: float
) -> Array[HamletLayout]:
	var out: Array[HamletLayout] = []
	var reach := radius + settings.clear_radius
	var lo := Vector2i(
		floori((x - reach) / settings.cell_size), floori((z - reach) / settings.cell_size)
	)
	var hi := Vector2i(
		floori((x + reach) / settings.cell_size), floori((z + reach) / settings.cell_size)
	)
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var hamlet := layout(Vector2i(cx, cz), settings, sampler, world_seed, water)
			if (
				hamlet != null
				and Vector2(hamlet.centre.x - x, hamlet.centre.z - z).length() <= radius
			):
				out.append(hamlet)
	return out


## Clearing circles touching the absolute rectangle [param rect]: (x, z, radius, everything) —
## [code]w[/code] is 1 for a footprint (no plant at all) and 0 for the area around the well
## (no tall plant). Usually empty.
static func circles_in(
	rect: Rect2, settings: HamletSettings, sampler: HeightSampler, world_seed: int, water: float
) -> PackedVector4Array:
	var out := PackedVector4Array()
	var centre := rect.get_center()
	var radius := rect.size.length() * 0.5 + settings.clear_radius
	for hamlet in near(centre.x, centre.y, radius, settings, sampler, world_seed, water):
		var grown := rect.grow(settings.clear_radius)
		if grown.has_point(Vector2(hamlet.centre.x, hamlet.centre.z)):
			out.append(Vector4(hamlet.centre.x, hamlet.centre.z, settings.clear_radius, 0.0))
		for i in hamlet.size():
			var p := hamlet.positions[i]
			if rect.grow(hamlet.radii[i]).has_point(Vector2(p.x, p.z)):
				out.append(Vector4(p.x, p.z, hamlet.radii[i] + 0.5, 1.0))
	return out


## Forgets every cached layout (tests).
static func clear_cache() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()


static func _make(
	cell: Vector2i, settings: HamletSettings, sampler: HeightSampler, world_seed: int, water: float
) -> HamletLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = HeightSampler.layer_seed(
		world_seed, SALT ^ (cell.x * 73856093) ^ (cell.y * 19349663)
	)
	if rng.randf() >= settings.chance:
		return null
	var resolver := sampler.resolver()
	if resolver == null:
		return null
	var margin := settings.site_radius + settings.clear_radius
	for attempt in settings.tries:
		var x := (
			(cell.x + 0.0) * settings.cell_size
			+ rng.randf_range(margin, settings.cell_size - margin)
		)
		var z := (
			(cell.y + 0.0) * settings.cell_size
			+ rng.randf_range(margin, settings.cell_size - margin)
		)
		var biome := _biome_fully(resolver, x, z, settings)
		if biome == &"" or not _flat_and_dry(x, z, settings, sampler, water):
			continue
		return _lay_out(cell, Vector3(x, sampler.height_at(x, z), z), biome, settings, sampler, rng)
	return null


# The biome at (x, z) if the whole site lies in it (no blend with a neighbour), else empty.
static func _biome_fully(
	resolver: BiomeResolver, x: float, z: float, settings: HamletSettings
) -> StringName:
	var ids: Array[StringName] = []
	for p: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var at := p * settings.clear_radius
		var weights := resolver.weights_at(x + at.x, z + at.y)
		if weights.size() != 1:
			return &""
		ids.append(weights.keys()[0])
	if ids.count(ids[0]) != ids.size() or not settings.biomes.has(ids[0]):
		return &""
	return ids[0]


# Whether every sample of the site's grid is above the water and the ground is gentle: between
# neighbouring samples it rises faster than max_slope at most a tenth of the time, and never
# faster than twice that (hills always have a steeper patch somewhere).
static func _flat_and_dry(
	x: float, z: float, settings: HamletSettings, sampler: HeightSampler, water: float
) -> bool:
	var n := ceili(settings.site_radius / settings.site_step)
	var rise := tan(deg_to_rad(settings.max_slope)) * settings.site_step
	var previous_row := PackedFloat32Array()
	var steps := 0
	var steep := 0
	for j in range(-n, n + 1):
		var row := PackedFloat32Array()
		for i in range(-n, n + 1):
			var h := sampler.height_at(x + i * settings.site_step, z + j * settings.site_step)
			if h < water + settings.above_water:
				return false
			for other: float in [
				row[row.size() - 1] if not row.is_empty() else NAN,
				previous_row[row.size()] if not previous_row.is_empty() else NAN
			]:
				if is_nan(other):
					continue
				var d := absf(h - other)
				if d > rise * 2.0:
					return false
				steps += 1
				steep += int(d > rise)
			row.append(h)
		previous_row = row
	return steep <= steps * 0.1


static func _lay_out(
	cell: Vector2i,
	centre: Vector3,
	biome: StringName,
	settings: HamletSettings,
	sampler: HeightSampler,
	rng: RandomNumberGenerator
) -> HamletLayout:
	var hamlet := HamletLayout.new()
	hamlet.cell = cell
	hamlet.centre = centre
	hamlet.biome = biome
	hamlet.add(&"well", centre, rng.randf() * TAU, settings.piece(&"well").footprint)
	var count := rng.randi_range(settings.houses.x, settings.houses.y)
	var turn := rng.randf() * TAU
	var stable_slot := rng.randi() % (count + 1)
	for slot in count + 1:  # the houses and the stable share the ring
		var angle := turn + TAU * slot / (count + 1) + rng.randf_range(-0.15, 0.15)
		var id := (
			&"stable"
			if slot == stable_slot
			else settings.house_ids[rng.randi() % settings.house_ids.size()]
		)
		var piece := settings.piece(id)
		for attempt in 4:
			var distance := (
				rng.randf_range(settings.ring.x, settings.ring.y) + piece.footprint * 0.5
			)
			var at := centre + Vector3(sin(angle), 0.0, cos(angle)) * distance
			if hamlet.overlaps(at.x, at.z, piece.footprint):
				continue
			at.y = sampler.height_at(at.x, at.z)
			var facing := atan2(centre.x - at.x, centre.z - at.z)  # its front towards the well
			hamlet.add(id, at, facing, piece.footprint)
			if id == &"stable":
				_add_pen(hamlet, at, facing, settings, sampler)
			break
	var house_count := hamlet.size()
	for h in range(1, house_count):
		if hamlet.ids[h] == &"stable" or hamlet.ids[h] == &"fence":
			continue
		for n in rng.randi_range(settings.props_per_house.x, settings.props_per_house.y):
			var id := settings.prop_ids[rng.randi() % settings.prop_ids.size()]
			var piece := settings.piece(id)
			var angle := rng.randf() * TAU
			var at := (
				hamlet.positions[h]
				+ (
					Vector3(sin(angle), 0.0, cos(angle))
					* (hamlet.radii[h] + piece.footprint + rng.randf_range(0.3, 1.5))
				)
			)
			if hamlet.overlaps(at.x, at.z, piece.footprint):
				continue
			at.y = sampler.height_at(at.x, at.z)
			hamlet.add(id, at, rng.randf() * TAU, piece.footprint)
	# Last (so the pieces above stay the same): a vegetable patch and a hens' nest, each by a
	# house, on the yard side.
	for id: StringName in [settings.patch_id, settings.nest_id]:
		var piece := settings.piece(id)
		if piece == null:
			continue
		for h in range(1, house_count):
			if not settings.house_ids.has(hamlet.ids[h]):
				continue
			var house := hamlet.positions[h]
			var toward := Vector3(centre.x - house.x, 0.0, centre.z - house.z).normalized()
			var side := (
				Vector3(toward.z, 0.0, -toward.x) * (1.0 if id == settings.patch_id else -1.0)
			)
			var at := (
				house
				+ (toward * 0.6 + side).normalized() * (hamlet.radii[h] + piece.footprint + 0.8)
			)
			if hamlet.overlaps(at.x, at.z, piece.footprint):
				continue
			at.y = sampler.height_at(at.x, at.z)
			hamlet.add(id, at, atan2(toward.x, toward.z), piece.footprint)
			break
	return hamlet


# A square pen of fence panels beside the stable (towards the outside of the ring).
static func _add_pen(
	hamlet: HamletLayout,
	stable: Vector3,
	facing: float,
	settings: HamletSettings,
	sampler: HeightSampler
) -> void:
	var fence := settings.piece(&"fence")
	var panel := fence.footprint * 2.0  # a panel's length
	var half := panel * 2.0  # 4 panels a side
	var outward := Vector3(-sin(facing), 0.0, -cos(facing))
	var side := Vector3(cos(facing), 0.0, -sin(facing))
	var pen := stable + side * (hamlet.radii[hamlet.size() - 1] + half + 1.0)
	if hamlet.overlaps(pen.x, pen.z, half * 1.2):
		pen = stable + outward * (hamlet.radii[hamlet.size() - 1] + half + 1.0)
		if hamlet.overlaps(pen.x, pen.z, half * 1.2):
			return
	pen.y = sampler.height_at(pen.x, pen.z)
	hamlet.pen = pen
	hamlet.pen_half = half
	for edge in 4:
		var normal := Vector3(sin(facing + edge * PI * 0.5), 0.0, cos(facing + edge * PI * 0.5))
		var along := Vector3(normal.z, 0.0, -normal.x)
		for k in 4:
			var at := pen + normal * half + along * (-half + panel * (k + 0.5))
			at.y = sampler.height_at(at.x, at.z)
			hamlet.add(&"fence", at, facing + edge * PI * 0.5, fence.footprint * 0.5)
