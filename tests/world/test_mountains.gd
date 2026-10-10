## Tests for the mountain band (Phase 17, ADR-008): high snowy peaks, passes that always let
## the fox cross, gentle edges thanks to the relief profile, snow line rules for plants, and
## the profile being neutral for every other biome.
extends GdUnitTestSuite

const SETTINGS: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SPECIES: AnimalSpecies = preload("res://data/species/fox.tres")
const SEEDS: Array[int] = [12345, 777, 2024]
## Grid step of the crossing search (m).
const STEP: float = 8.0

var _band: BiomeDefinition


func before() -> void:
	for biome in SETTINGS.biomes.biomes:
		if biome.id == &"mountains":
			_band = biome


# Start (effective distance) of the first mountain band.
func _start(resolver: BiomeResolver) -> float:
	return resolver.band_start(SETTINGS.biomes.biomes.find(_band))


func test_peaks_rise_well_above_the_snow_line_and_snow_covers_part_of_the_band() -> void:
	for seed_value in SEEDS:
		var sampler := HeightSampler.new(SETTINGS, seed_value)
		var start := _start(sampler.resolver())
		var highest := -INF
		var snowy := 0
		var n := 0
		for a in 120:
			for i in 30:
				var p := Vector2.from_angle(a * TAU / 120.0) * (start + (i + 0.5) * 40.0)
				var h := sampler.height_at(p.x, p.y)
				highest = maxf(highest, h)
				snowy += int(h > SETTINGS.snow_line)
				n += 1
		assert_float(highest).is_greater(SETTINGS.snow_line + 50.0)
		assert_float(float(snowy) / n).is_between(0.1, 0.35)  # caps, not a snowfield


func test_only_the_mountains_reach_the_snow_line() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var resolver := sampler.resolver()
	for b in SETTINGS.biomes.biomes.size():
		if SETTINGS.biomes.biomes[b] == _band:
			continue
		for a in 90:
			for i in 16:
				var p := Vector2.from_angle(a * TAU / 90.0) * (resolver.band_start(b) + i * 50.0)
				if resolver.dominant_at(p.x, p.y) != _band:
					assert_float(sampler.height_at(p.x, p.y)).is_less(SETTINGS.snow_line - 20.0)


func test_passes_always_cross_the_band() -> void:
	# A walk on an 8 m grid, never steeper than the fox can climb, from the foothills to the
	# meadow beyond, in strips 400 m wide around the band.
	var rise := STEP * tan(deg_to_rad(SPECIES.max_slope_degrees))
	for seed_value in SEEDS:
		var sampler := HeightSampler.new(SETTINGS, seed_value)
		var start := _start(sampler.resolver())
		for strip in 6:
			var angle := strip * TAU / 6.0 + 0.3
			(
				assert_bool(
					_crosses(sampler, angle, start - 60.0, start + _band.band_width + 60.0, rise)
				)
				. override_failure_message("seed %d strip %d has no pass" % [seed_value, strip])
				. is_true()
			)


func test_the_band_rises_to_a_crest_and_comes_down_gently() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var start := _start(sampler.resolver())
	var means := PackedFloat32Array()
	for t in 7:  # edge, …, middle, …, edge
		var sum := 0.0
		for a in 120:
			var p := Vector2.from_angle(a * TAU / 120.0) * (start + t / 6.0 * _band.band_width)
			sum += sampler.height_at(p.x, p.y)
		means.append(sum / 120.0)
	assert_float(means[3]).is_greater(means[0] + 40.0)
	assert_float(means[3]).is_greater(means[6] + 40.0)
	# The outer edge (into the next meadow): its mean slope stays walkable.
	var slope := 0.0
	var n := 0
	for a in 180:
		for r in 5:
			var p := (
				Vector2.from_angle(a * TAU / 180.0) * (start + _band.band_width - 50.0 + r * 25.0)
			)
			var dx := (sampler.height_at(p.x + 1.0, p.y) - sampler.height_at(p.x - 1.0, p.y)) * 0.5
			var dz := (sampler.height_at(p.x, p.y + 1.0) - sampler.height_at(p.x, p.y - 1.0)) * 0.5
			slope += rad_to_deg(atan(Vector2(dx, dz).length()))
			n += 1
	assert_float(slope / n).is_less(20.0)


func test_the_relief_profile_is_neutral_elsewhere_and_bounded() -> void:
	for biome in SETTINGS.biomes.biomes:
		if biome != _band:
			assert_float(biome.edge_relief).is_equal(1.0)
	assert_float(_band.edge_relief).is_less(0.5)
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var resolver := sampler.resolver()
	var start := _start(resolver)
	var bound := sampler.max_deviation()
	var blend := BiomeBlend.new()
	for a in 60:
		for i in 40:
			var p := Vector2.from_angle(a * TAU / 60.0) * (start - 100.0 + i * 35.0)
			assert_float(absf(sampler.height_at(p.x, p.y) - SETTINGS.base_height)).is_less_equal(
				bound
			)
	# Inside the band the heights vary with the profile, so a chunk is never "uniform" for
	# heights; for vegetation (biome and colours only) it is.
	var middle := Vector2(start + _band.band_width * 0.5, 0.0)
	var p_mid := Vector2.from_angle(1.0) * middle.x
	assert_bool(resolver.uniform_blend(p_mid.x, p_mid.y, 45.0, blend)).is_false()
	assert_bool(resolver.uniform_blend(p_mid.x, p_mid.y, 45.0, blend, false)).is_true()
	assert_object(blend.primary).is_same(_band)


func test_no_plant_grows_above_the_snow_line() -> void:
	# Only the mountains reach it (test_only_the_mountains_reach_the_snow_line), so only their
	# plants need a limit; rocks poke out of the snow.
	for entry in _band.vegetation:
		if entry.type.resource_path.get_file().begins_with("rock_"):
			continue
		var top := SETTINGS.sea_level + entry.max_height
		assert_float(top).is_less_equal(SETTINGS.snow_line - SETTINGS.snow_blend)


func test_the_snow_reaches_the_terrain_shader() -> void:
	assert_bool(ProjectSettings.has_setting("shader_globals/snow_line")).is_true()
	assert_bool(ProjectSettings.has_setting("shader_globals/snow_blend")).is_true()
	var code := (load("res://shaders/terrain.gdshader") as Shader).code
	assert_str(code).contains("global uniform float snow_line")
	assert_float(SETTINGS.snow_line).is_between(80.0, 120.0)


# Breadth-first search over a strip at [param angle], from effective distance [param from] to
# [param to], ±200 m to the side, with steps no higher than [param rise].
func _crosses(sampler: HeightSampler, angle: float, from: float, to: float, rise: float) -> bool:
	var along := Vector2.from_angle(angle)
	var side := along.orthogonal()
	var rows := int((to - from) / STEP) + 1
	var cols := int(400.0 / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(rows * cols)
	for r in rows:
		for c in cols:
			var p := along * (from + r * STEP) + side * ((c - cols / 2) * STEP)
			heights[r * cols + c] = sampler.height_at(p.x, p.y)
	var seen := PackedByteArray()
	seen.resize(rows * cols)
	var queue := PackedInt32Array()
	for c in cols:
		queue.append(c)
		seen[c] = 1
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var r := cell / cols
		var c := cell % cols
		if r == rows - 1:
			return true
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nr := r + step.x
			var nc := c + step.y
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			var next := nr * cols + nc
			if seen[next] == 0 and absf(heights[next] - heights[cell]) <= rise:
				seen[next] = 1
				queue.append(next)
	return false
