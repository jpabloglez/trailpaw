## Tests for the desert and the savanna (Phase 18, ADR-009): dunes that rise and fall across the
## wind, flat-topped mesas standing well above the sand, a band that can always be crossed, the
## savanna's gentle ground, and the sand layers being neutral in every other biome.
extends GdUnitTestSuite

const SETTINGS: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SPECIES: AnimalSpecies = preload("res://data/species/fox.tres")
const GridWalk := preload("res://tests/world/grid_walk.gd")
const SEEDS: Array[int] = [12345, 777, 2024]
## A mesa top (seed 12345, test_height_sampler).
const MESA := Vector2(-5737.877, -653.7481)

var _desert: BiomeDefinition
var _savanna: BiomeDefinition


func before() -> void:
	for biome in SETTINGS.biomes.biomes:
		if biome.id == &"desert":
			_desert = biome
		elif biome.id == &"savanna":
			_savanna = biome


func _start(resolver: BiomeResolver, biome: BiomeDefinition) -> float:
	return resolver.band_start(SETTINGS.biomes.biomes.find(biome))


func test_the_desert_follows_the_mountains_and_the_savanna_closes_the_cycle() -> void:
	var biomes := SETTINGS.biomes.biomes
	assert_str(String(biomes[biomes.find(_desert) - 1].id)).is_equal("mountains")
	assert_int(biomes.find(_savanna)).is_equal(biomes.find(_desert) + 1)
	assert_int(biomes.find(_savanna)).is_equal(biomes.size() - 1)  # then back to the meadow
	assert_float(_desert.warmth).is_greater(1.0)  # hotter than the hills


func test_dunes_rise_and_fall_across_the_wind() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var wind := Vector2.from_angle(deg_to_rad(SETTINGS.dune_direction_degrees))
	var at := Vector2(-5900.0, -1500.0)  # dunes, no mesa (test_height_sampler)
	var lows := 0
	var highs := 0
	var previous := sampler.height_at(at.x, at.y)
	var rising := false
	for step in range(1, 240):  # 240 m across the crests
		var p := at + wind * step
		var h := sampler.height_at(p.x, p.y)
		if h > previous and not rising:
			lows += 1
		elif h < previous and rising:
			highs += 1
		rising = h > previous
		previous = h
	var crests := SETTINGS.dune_wavelength
	assert_int(highs).is_between(int(240.0 / crests * 0.5), int(240.0 / crests * 3.0))
	assert_int(lows).is_greater(1)


func test_mesas_are_flat_topped_and_stand_well_above_the_sand() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	# Somewhere on the mesa there is a patch 40 m across, flat within 1 m: its top (no dunes
	# cross it; they rise ≈ 5 m within 20 m of a crest).
	var top := -INF
	for gx in range(-15, 16):
		for gz in range(-15, 16):
			var c := MESA + Vector2(gx, gz) * 4.0
			var h := sampler.height_at(c.x, c.y)
			var flat := true
			for a in 8:
				var p := c + Vector2.from_angle(a * TAU / 8.0) * 20.0
				flat = flat and absf(sampler.height_at(p.x, p.y) - h) < 1.0
			if flat:
				top = maxf(top, h)
	assert_float(top).is_greater(-INF)
	var sand := INF
	for a in 16:
		var p := MESA + Vector2.from_angle(a * TAU / 16.0) * 160.0
		sand = minf(sand, sampler.height_at(p.x, p.y))
	assert_float(top - sand).is_greater(12.0)


func test_the_desert_and_savanna_can_always_be_crossed() -> void:
	var rise := GridWalk.STEP * tan(deg_to_rad(SPECIES.max_slope_degrees))
	for seed_value in SEEDS:
		var sampler := HeightSampler.new(SETTINGS, seed_value)
		var start := _start(sampler.resolver(), _desert)
		var end := start + _desert.band_width + _savanna.band_width
		for strip in 6:
			var angle := strip * TAU / 6.0 + 0.7
			(
				assert_bool(GridWalk.crosses(sampler, angle, start - 60.0, end + 60.0, rise))
				. override_failure_message("seed %d strip %d" % [seed_value, strip])
				. is_true()
			)


func test_the_savanna_is_gentle_and_dry_above_the_water() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var start := _start(sampler.resolver(), _savanna)
	var steep := 0
	var n := 0
	for a in 60:
		for r in 8:
			var p := Vector2.from_angle(a * TAU / 60.0) * (start + 200.0 + r * 50.0)
			var dx := (sampler.height_at(p.x + 1.0, p.y) - sampler.height_at(p.x - 1.0, p.y)) * 0.5
			var dz := (sampler.height_at(p.x, p.y + 1.0) - sampler.height_at(p.x, p.y - 1.0)) * 0.5
			steep += int(Vector2(dx, dz).length() > tan(deg_to_rad(25.0)))
			n += 1
	assert_float(float(steep) / n).is_less(0.03)
	assert_float(_savanna.dune_scale + _savanna.mesa_scale).is_equal(0.0)


func test_the_sand_layers_are_neutral_elsewhere_and_bounded() -> void:
	for biome in SETTINGS.biomes.biomes:
		if biome != _desert:
			assert_float(biome.dune_scale + biome.mesa_scale).is_equal(0.0)
	assert_float(_desert.dune_scale).is_greater(0.0)
	assert_float(_desert.mesa_scale).is_greater(0.0)
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var start := _start(sampler.resolver(), _desert)
	var bound := sampler.max_deviation()
	for a in 60:
		for i in 30:
			var p := Vector2.from_angle(a * TAU / 60.0) * (start - 100.0 + i * 40.0)
			assert_float(absf(sampler.height_at(p.x, p.y) - SETTINGS.base_height)).is_less_equal(
				bound
			)
	# A chunk wholly in the desert still takes the uniform fast path, now with the sand
	# scales: its heights match the per-sample function exactly.
	var blend := BiomeBlend.new()
	var middle := Vector2.from_angle(0.4) * (start + _desert.band_width * 0.5)
	assert_bool(sampler.resolver().uniform_blend(middle.x, middle.y, 45.0, blend)).is_true()
	var fast := sampler.sample_with_modifiers(
		middle.x,
		middle.y,
		blend.height_offset,
		blend.continental_scale,
		blend.detail_scale,
		blend.ridged_scale,
		blend.dune_scale,
		blend.mesa_scale
	)
	assert_float(fast).is_equal_approx(sampler.height_at(middle.x, middle.y), 1e-5)


func test_desert_chunks_carry_the_dunes_and_mesas() -> void:
	# The chunk generator's fast path (a chunk wholly in one band) must pass the sand scales on:
	# its heights equal the height function at every sample.
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var res := SETTINGS.resolution_for_lod(0)
	var step := SETTINGS.step_for_lod(0)
	var resolver := sampler.resolver()
	var middle := Vector2.from_angle(0.4) * (_start(resolver, _desert) + _desert.band_width * 0.5)
	var coord := Vector2i((middle / SETTINGS.chunk_size).floor())
	var span := float(res + 1) * step
	var blend := BiomeBlend.new()
	var centre := (Vector2(coord) * (res - 1) - Vector2.ONE) * step + Vector2.ONE * span * 0.5
	assert_bool(resolver.uniform_blend(centre.x, centre.y, span * 0.75, blend)).is_true()
	var heights := ChunkGenerator.sample_apron(sampler, coord, res, step)
	var side := res + 2
	for k in [0, side + 3, side * 9 + 17, side * side - 1]:
		var x := float(coord.x * (res - 1) - 1 + k % side) * step
		var z := float(coord.y * (res - 1) - 1 + k / side) * step
		assert_float(heights[k]).is_equal_approx(sampler.height_at(x, z), 1e-4)


func test_the_bound_counts_the_sand_layers_and_the_scales_blend_across_borders() -> void:
	var flat: TerrainSettings = SETTINGS.duplicate()
	flat.dune_amplitude = 0.0
	flat.mesa_amplitude = 0.0
	var with_sand := HeightSampler.new(SETTINGS, SEEDS[0]).max_deviation()
	var without := HeightSampler.new(flat, SEEDS[0]).max_deviation()
	var expected := (
		SETTINGS.dune_amplitude * _desert.dune_scale + SETTINGS.mesa_amplitude * _desert.mesa_scale
	)
	assert_float(with_sand - without).is_equal_approx(expected, 1e-4)
	# Across the desert's borders the scales fade with the biome weights (no step).
	var resolver := BiomeResolver.new(SETTINGS.biomes, SEEDS[0])
	var blend := BiomeBlend.new()
	var start := _start(resolver, _desert)
	for edge: float in [start, start + _desert.band_width]:
		for d in range(-70, 71, 10):
			var p := Vector2.from_angle(1.1) * (edge + d)
			resolver.blend_into(p.x, p.y, blend)
			var desert_weight := resolver.weights_at(p.x, p.y).get(&"desert", 0.0) as float
			assert_float(blend.dune_scale).is_equal_approx(desert_weight * _desert.dune_scale, 1e-4)
			assert_float(blend.mesa_scale).is_equal_approx(desert_weight * _desert.mesa_scale, 1e-4)
