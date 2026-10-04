## Tests for [HeightSampler] determinism and the terrain settings data.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const SPECIES_PATH: String = "res://data/species/placeholder.tres"
const SEED: int = 12345

var _settings: TerrainSettings


func before() -> void:
	_settings = load(SETTINGS_PATH)


## Samples a grid of heights; includes negative and far-away coordinates.
func _grid(sampler: HeightSampler) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	for i in 20:
		for j in 20:
			heights.append(sampler.height_at(-5000.0 + i * 517.3, -3000.0 + j * 311.7))
	return heights


func test_settings_are_valid() -> void:
	assert_array(Array(_settings.get_validation_errors())).is_empty()


func test_unconfigured_settings_are_invalid() -> void:
	assert_bool(TerrainSettings.new().is_valid()).is_false()


func test_same_seed_gives_identical_heights() -> void:
	var a := _grid(HeightSampler.new(_settings, SEED))
	var b := _grid(HeightSampler.new(_settings, SEED))
	assert_array(Array(a)).is_equal(Array(b))


func test_copied_settings_give_identical_heights() -> void:
	# Worker threads get their own duplicate of the settings.
	var copy := _settings.duplicate() as TerrainSettings
	var a := _grid(HeightSampler.new(_settings, SEED))
	var b := _grid(HeightSampler.new(copy, SEED))
	assert_array(Array(a)).is_equal(Array(b))


func test_different_seed_changes_heights() -> void:
	var a := _grid(HeightSampler.new(_settings, SEED))
	var b := _grid(HeightSampler.new(_settings, SEED + 1))
	assert_array(Array(a)).is_not_equal(Array(b))


func test_layer_seeds_are_distinct_and_stable() -> void:
	var seeds := {}
	for salt: int in HeightSampler.LAYER_SALT:
		seeds[HeightSampler.layer_seed(SEED, salt)] = true
	assert_int(seeds.size()).is_equal(HeightSampler.LAYER_SALT.size())
	assert_int(HeightSampler.layer_seed(SEED, 7)).is_equal(HeightSampler.layer_seed(SEED, 7))


func test_heights_stay_within_bound() -> void:
	var sampler := HeightSampler.new(_settings, SEED)
	var bound := sampler.max_deviation() + 1e-3
	for h: float in _grid(sampler):
		assert_float(absf(h - _settings.base_height)).is_less_equal(bound)


func test_terrain_is_varied() -> void:
	var heights := _grid(HeightSampler.new(_settings, SEED))
	var lo := INF
	var hi := -INF
	for h: float in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	assert_float(hi - lo).is_greater(5.0)


## Golden values: fail loudly if an engine upgrade or code change alters the world a
## given seed produces (that would silently break saves). Update deliberately, with an ADR
## (last change: ADR-006, the wetland band after the river valley).
func test_golden_heights_for_reference_seed() -> void:
	var sampler := HeightSampler.new(_settings, SEED)
	assert_int(HeightSampler.layer_seed(SEED, HeightSampler.LAYER_SALT[0])).is_equal(1883851918)
	assert_float(sampler.height_at(0.0, 0.0)).is_equal_approx(4.4, 1e-4)
	assert_float(sampler.height_at(1234.5, -678.25)).is_equal_approx(5.594238, 1e-4)
	assert_float(sampler.height_at(-9000.0, 4200.0)).is_equal_approx(3.591054, 1e-4)


func test_terrain_is_walkable_in_every_biome() -> void:
	var sampler := HeightSampler.new(_settings, SEED)
	var resolver := sampler.resolver()
	var limit := tan(deg_to_rad((load(SPECIES_PATH) as AnimalSpecies).max_slope_degrees))
	for b in _settings.biomes.biomes.size():
		var steep := 0
		var total := 0
		for a in 24:
			for r in 12:
				var p := (
					Vector2.from_angle(a * TAU / 24.0) * (resolver.band_start(b) + 260.0 + r * 25.0)
				)
				var dx := (
					(sampler.height_at(p.x + 1.0, p.y) - sampler.height_at(p.x - 1.0, p.y)) * 0.5
				)
				var dz := (
					(sampler.height_at(p.x, p.y + 1.0) - sampler.height_at(p.x, p.y - 1.0)) * 0.5
				)
				if Vector2(dx, dz).length() > limit:
					steep += 1
				total += 1
		assert_float(float(steep) / total).is_less(0.02)


func test_biome_shapes_the_terrain_valley_low_hills_high() -> void:
	var sampler := HeightSampler.new(_settings, SEED)
	var resolver := sampler.resolver()
	var means := {}
	for b in _settings.biomes.biomes.size():
		var sum := 0.0
		var n := 0
		for a in 36:
			for r in 10:
				var p := (
					Vector2.from_angle(a * TAU / 36.0) * (resolver.band_start(b) + 250.0 + r * 30.0)
				)
				if resolver.dominant_at(p.x, p.y) == _settings.biomes.biomes[b]:
					sum += sampler.height_at(p.x, p.y)
					n += 1
		means[_settings.biomes.biomes[b].id] = sum / n
	assert_float(means[&"river_valley"]).is_less(means[&"meadow"])
	assert_float(means[&"meadow"]).is_less(means[&"hills"])


func test_plain_noise_without_biome_table() -> void:
	var plain := _settings.duplicate() as TerrainSettings
	plain.biomes = null
	var sampler := HeightSampler.new(plain, SEED)
	assert_object(sampler.resolver()).is_null()
	assert_float(absf(sampler.height_at(10.0, 20.0))).is_less_equal(sampler.max_deviation())
