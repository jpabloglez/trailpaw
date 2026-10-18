class_name IslandPlan
extends RefCounted
## Pure, deterministic placement of island treasures (Phase 19). The world is cut into square
## cells of [member IslandSettings.cell_size]; each cell, seeded per (world seed, cell), tries a
## few random spots in a treasure biome (the lakes). A spot above the water climbs to the top of
## its land, and that top is an island when [constant RAYS] rays from it all reach the water
## within [member IslandSettings.max_reach] (none closer than [member IslandSettings.min_reach]).
## The top must lie in the cell, so an island crossing a cell border has one treasure at most.
## [br][br]
## Terrain heights are not changed. Tall plants are cleared around a treasure
## ([method circles_in]).
## [br][br]
## Thread-safe: computed once per (seed, cell) under a mutex and cached for the session, so chunk
## workers and the main thread see the same treasures. Budget: outside the treasure biomes a
## cell costs [member IslandSettings.tries] biome lookups; inside, ≤ tries × (1 + 8 × climb
## steps + RAYS × max_reach / ray_step) height samples (≈ 6500; typically a few hundred), once.

## What an island holds.
enum Treasure { ANCIENT_TREE, RARE_FLOWERS, OTTER_DEN }

## Rays cast from an island's top: enough that a peninsula's neck does not slip between them.
const RAYS: int = 32
## Salt for island seeds.
const SALT: int = 0x15A4D
## Display names of the treasures, in the order of [enum Treasure].
const NAMES: Array[String] = ["An ancient tree", "Rare flowers", "An otter den"]

static var _cache: Dictionary = {}  # Vector3i(seed, cell.x, cell.y) → IslandTreasure or null
static var _mutex := Mutex.new()


## The treasure of [param cell], or null (cached).
static func treasure(
	cell: Vector2i, settings: IslandSettings, sampler: HeightSampler, world_seed: int, water: float
) -> IslandTreasure:
	var key := Vector3i(world_seed, cell.x, cell.y)
	_mutex.lock()
	var found: bool = _cache.has(key)
	var cached: IslandTreasure = _cache.get(key)
	_mutex.unlock()
	if found:
		return cached
	var made := _make(cell, settings, sampler, world_seed, water)
	_mutex.lock()
	_cache[key] = made
	_mutex.unlock()
	return made


## Whether [param cell] has been worked out already ([method treasure] would not compute).
static func is_cached(cell: Vector2i, world_seed: int) -> bool:
	_mutex.lock()
	var found: bool = _cache.has(Vector3i(world_seed, cell.x, cell.y))
	_mutex.unlock()
	return found


## Treasures within [param radius] of absolute ([param x], [param z]).
static func near(
	x: float,
	z: float,
	radius: float,
	settings: IslandSettings,
	sampler: HeightSampler,
	world_seed: int,
	water: float
) -> Array[IslandTreasure]:
	var out: Array[IslandTreasure] = []
	var lo := Vector2i(
		floori((x - radius) / settings.cell_size), floori((z - radius) / settings.cell_size)
	)
	var hi := Vector2i(
		floori((x + radius) / settings.cell_size), floori((z + radius) / settings.cell_size)
	)
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var found := treasure(Vector2i(cx, cz), settings, sampler, world_seed, water)
			if found != null and Vector2(found.centre.x - x, found.centre.z - z).length() <= radius:
				out.append(found)
	return out


## Clearings touching the absolute rectangle [param rect], as the [VegetationScatterer] reads
## them: (x, z, radius, 0) — no tall plant inside. Usually empty.
static func circles_in(
	rect: Rect2, settings: IslandSettings, sampler: HeightSampler, world_seed: int, water: float
) -> PackedVector4Array:
	var out := PackedVector4Array()
	var centre := rect.get_center()
	var radius := rect.size.length() * 0.5 + settings.clear_radius
	for found in near(centre.x, centre.y, radius, settings, sampler, world_seed, water):
		out.append(Vector4(found.centre.x, found.centre.z, settings.clear_radius, 0.0))
	return out


## Forgets every cached treasure (tests).
static func clear_cache() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()


static func _make(
	cell: Vector2i, settings: IslandSettings, sampler: HeightSampler, world_seed: int, water: float
) -> IslandTreasure:
	var resolver := sampler.resolver()
	if resolver == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = HeightSampler.layer_seed(
		world_seed, SALT ^ (cell.x * 73856093) ^ (cell.y * 19349663)
	)
	if rng.randf() >= settings.chance:
		return null
	var area := Rect2(Vector2(cell) * settings.cell_size, Vector2.ONE * settings.cell_size)
	for attempt in settings.tries:
		var spot := area.position + Vector2(rng.randf(), rng.randf()) * settings.cell_size
		if not settings.biomes.has(resolver.dominant_at(spot.x, spot.y).id):
			continue
		if sampler.height_at(spot.x, spot.y) < water + settings.above_water:
			continue
		var top := _climb(spot, settings, sampler)
		if (
			not area.has_point(top)
			or not settings.biomes.has(resolver.dominant_at(top.x, top.y).id)
		):
			continue
		var reach := _reach(top, settings, sampler, water)
		if reach < 0.0:
			continue
		var made := IslandTreasure.new()
		made.cell = cell
		made.centre = Vector3(top.x, sampler.height_at(top.x, top.y), top.y)
		made.radius = reach
		made.kind = rng.rand_weighted(settings.weights)
		made.seed = rng.randi()
		return made
	return null


# Walks uphill from [param spot] to the top of its land.
static func _climb(spot: Vector2, settings: IslandSettings, sampler: HeightSampler) -> Vector2:
	var at := spot
	var height := sampler.height_at(at.x, at.y)
	for step in settings.climb_steps:
		var best := at
		for d in 8:
			var p := at + Vector2.from_angle(d * TAU / 8.0) * settings.climb_step
			var h := sampler.height_at(p.x, p.y)
			if h > height:
				height = h
				best = p
		if best == at:
			break
		at = best
	return at


# Mean distance to the water along [constant RAYS] rays from [param top], or −1 when one of
# them finds no water within reach (the mainland) or finds it too close (a mere rock).
static func _reach(
	top: Vector2, settings: IslandSettings, sampler: HeightSampler, water: float
) -> float:
	var total := 0.0
	for d in RAYS:
		var along := Vector2.from_angle((d + 0.5) * TAU / RAYS)
		var hit := -1.0
		var r := settings.ray_step
		while r <= settings.max_reach:
			var p := top + along * r
			if sampler.height_at(p.x, p.y) < water:
				hit = r
				break
			r += settings.ray_step
		if hit < 0.0 or hit < settings.min_reach:
			return -1.0
		total += hit
	return total / RAYS
