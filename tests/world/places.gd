## Finds places of the world for the tests (a band's point, its highest point…) from the
## height function, instead of fixed coordinates that move whenever a band is added
## (Phase 19: the lakes moved the mountains, desert and savanna out by 800 m).
extends RefCounted


## Effective distance where the first band of [param id] starts.
static func band_start(settings: TerrainSettings, sampler: HeightSampler, id: StringName) -> float:
	for b in settings.biomes.biomes.size():
		if settings.biomes.biomes[b].id == id:
			return sampler.resolver().band_start(b)
	return -1.0


static func band_width(settings: TerrainSettings, id: StringName) -> float:
	for biome in settings.biomes.biomes:
		if biome.id == id:
			return biome.band_width
	return 0.0


## A point (absolute X, Z) [param fraction] of the way across the first band of [param id],
## at [param angle] or the nearest angle after it where that band really is the biome there.
static func point_in(
	settings: TerrainSettings,
	sampler: HeightSampler,
	id: StringName,
	fraction: float = 0.5,
	angle: float = 0.3
) -> Vector2:
	var d := band_start(settings, sampler, id) + band_width(settings, id) * fraction
	for step in 360:
		var p := Vector2.from_angle(angle + step * TAU / 360.0) * d
		if sampler.resolver().dominant_at(p.x, p.y).id == id:
			return p
	return Vector2.INF


## The highest point (absolute X, height, Z) of the first band of [param id], sampled on
## [param rings] × [param angles] points between [param from] and [param to] of its width.
static func highest_in(
	settings: TerrainSettings,
	sampler: HeightSampler,
	id: StringName,
	from: float = 0.1,
	to: float = 0.9,
	rings: int = 16,
	angles: int = 360
) -> Vector3:
	var start := band_start(settings, sampler, id)
	var width := band_width(settings, id)
	var best := Vector3(0.0, -INF, 0.0)
	for a in angles:
		for r in rings:
			var p := (
				Vector2.from_angle(a * TAU / angles)
				* (start + width * lerpf(from, to, r / maxf(rings - 1, 1)))
			)
			var h := sampler.height_at(p.x, p.y)
			if h > best.y and sampler.resolver().dominant_at(p.x, p.y).id == id:
				best = Vector3(p.x, h, p.y)
	return best
