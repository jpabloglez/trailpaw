## Tests for the oases (Phase 18): deterministic bowls in the desert only, holding water, ringed
## with palms that grow nowhere else, close enough to scent from anywhere in the desert.
extends GdUnitTestSuite

const SETTINGS: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SNIFF: SniffSettings = preload("res://data/interaction/sniff.tres")
const FOX: AnimalSpecies = preload("res://data/species/fox.tres")
const SEEDS: Array[int] = [12345, 777, 2024]
## A full oasis (seed 12345): its centre.
const OASIS := Vector2(5616.176, 152.6471)
const PALMS: Array[StringName] = [&"tree_palm", &"tree_palmTall", &"tree_palmShort"]

var _desert: BiomeDefinition


func before() -> void:
	for biome in SETTINGS.biomes.biomes:
		if biome.id == &"desert":
			_desert = biome


# Oasis centres of the desert band (absolute X, Z) that are really there, wholly in the desert.
func _full_oases(sampler: HeightSampler) -> Array[Vector2]:
	var resolver := sampler.resolver()
	var start := resolver.band_start(SETTINGS.biomes.biomes.find(_desert))
	var seen := {}
	var out: Array[Vector2] = []
	for a in 360:
		for i in 10:
			var p := Vector2.from_angle(a * TAU / 360.0) * (start + (i + 0.5) * 100.0)
			var oasis := sampler.oasis_of(p.x, p.y)
			var key := Vector2i((p / SETTINGS.oasis_cell).floor())
			if not sampler.is_oasis(oasis) or seen.has(key):
				continue
			seen[key] = true
			var blend := BiomeBlend.new()
			sampler.sample(oasis.x, oasis.z, blend)
			if blend.oasis_scale == 1.0:
				out.append(Vector2(oasis.x, oasis.z))
	return out


func test_oases_are_deterministic_and_only_sink_the_desert() -> void:
	var one := HeightSampler.new(SETTINGS, SEEDS[0])
	var again := HeightSampler.new(SETTINGS, SEEDS[0])
	var other := HeightSampler.new(SETTINGS, SEEDS[1])
	assert_vector(one.oasis_of(OASIS.x, OASIS.y)).is_equal(again.oasis_of(OASIS.x, OASIS.y))
	assert_vector(one.oasis_of(OASIS.x, OASIS.y)).is_not_equal(other.oasis_of(OASIS.x, OASIS.y))
	for biome in SETTINGS.biomes.biomes:
		if biome != _desert:
			assert_float(biome.oasis_scale).is_equal(0.0)
	# Without oases, nothing changes away from the desert.
	var none: TerrainSettings = SETTINGS.duplicate()
	none.oasis_chance = 0.0
	var plain := HeightSampler.new(none, SEEDS[0])
	var resolver := one.resolver()
	for a in 90:
		for r in 30:
			var p := Vector2.from_angle(a * TAU / 90.0) * (r * 230.0 + 50.0)
			var weights := resolver.weights_at(p.x, p.y)
			if weights.has(&"desert"):
				continue
			assert_float(one.height_at(p.x, p.y)).is_equal(plain.height_at(p.x, p.y))


func test_every_full_oasis_holds_drinkable_water() -> void:
	for seed_value in SEEDS:
		var sampler := HeightSampler.new(SETTINGS, seed_value)
		var oases := _full_oases(sampler)
		assert_int(oases.size()).is_greater(20)
		for centre in oases:
			var bottom := sampler.height_at(centre.x, centre.y)
			assert_float(bottom).is_less_equal(SETTINGS.sea_level - 1.0)  # deep enough to drink
			# and the fox can walk down to the water from at least half the directions (a mesa
			# may stand at the rim, but inside the bowl the mesas fade out)
			var climb := 4.0 * tan(deg_to_rad(FOX.max_slope_degrees))
			var open := 0
			for side in 8:
				var ray := Vector2.from_angle(side * TAU / 8.0)
				var previous := bottom
				var walkable := true
				for step in range(1, int(SETTINGS.oasis_radius / 4.0) + 2):
					var p := centre + ray * step * 4.0
					var h := sampler.height_at(p.x, p.y)
					walkable = walkable and absf(h - previous) <= climb
					previous = h
				open += int(walkable)
			assert_int(open).override_failure_message(str(centre)).is_greater_equal(4)


func test_from_anywhere_in_the_desert_an_oasis_is_within_scent() -> void:
	for seed_value in SEEDS:
		var sampler := HeightSampler.new(SETTINGS, seed_value)
		var oases := _full_oases(sampler)
		var start := sampler.resolver().band_start(SETTINGS.biomes.biomes.find(_desert))
		for t in 120:
			var p := Vector2.from_angle(t * 2.399963) * (start + fmod(t * 37.0, _desert.band_width))
			var nearest := INF
			for centre in oases:
				nearest = minf(nearest, centre.distance_to(p))
			assert_float(nearest).is_less(SNIFF.scent_radius)
	# The fox's long-range scent itself finds the oasis.
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var from := OASIS + Vector2(400.0, 0.0)
	var scent := WaterScent.new(
		sampler, from, 600.0, SNIFF.scent_step, SETTINGS.sea_level, SNIFF.scent_min_depth
	)
	var water := scent.search()
	assert_bool(water != Vector3.INF).is_true()
	assert_float(Vector2(water.x, water.z).distance_to(OASIS)).is_less(SETTINGS.oasis_radius)


func test_palms_grow_around_the_oases_and_nowhere_else() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var scatterer := VegetationScatterer.new(SETTINGS.biomes)
	var size := SETTINGS.chunk_size
	var near := 0
	var stray := 0
	var centre := Vector2i((OASIS / size).floor())
	var coords: Array[Vector2i] = []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			coords.append(centre + Vector2i(dx, dz))
	for k in 12:  # and desert chunks elsewhere
		var p := Vector2.from_angle(k * 0.53) * (5200.0 + 100.0 + k * 70.0)
		coords.append(Vector2i((p / size).floor()))
	for c in coords:
		var data := ChunkGenerator.generate_with(c, 0, SETTINGS, sampler, scatterer, SEEDS[0])
		for id: StringName in PALMS:
			if not data.vegetation.has(id):
				continue
			var buffer: PackedFloat32Array = data.vegetation[id]
			for n in data.vegetation_count(id):
				var o := n * VegetationScatterer.FLOATS_PER_INSTANCE
				var at := Vector2(c.x * size + buffer[o + 3], c.y * size + buffer[o + 11])
				var oasis := sampler.oasis_of(at.x, at.y)
				var inside := Vector2(oasis.x, oasis.z).distance_to(at) < SETTINGS.oasis_radius
				if sampler.is_oasis(oasis) and inside:
					near += 1
				else:
					stray += 1
	assert_int(near).is_greater(8)
	assert_int(stray).is_less_equal(maxi(1, near / 20))


func test_no_oasis_opens_a_crater_in_a_mesa_and_the_bound_counts_them() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var start := sampler.resolver().band_start(SETTINGS.biomes.biomes.find(_desert))
	var checked := 0
	for a in 720:
		var p := Vector2.from_angle(a * TAU / 720.0) * (start + 500.0)
		var oasis := sampler.oasis_of(p.x, p.y)
		if oasis.y == 0.0:
			continue
		var on_mesa: bool = (
			sampler._sand.get_noise_2d(oasis.x, oasis.z)
			>= SETTINGS.mesa_threshold - HeightSampler.OASIS_MESA_MARGIN
		)
		assert_bool(sampler.is_oasis(oasis)).is_equal(not on_mesa)
		if on_mesa:
			checked += 1
			assert_float(sampler.height_at(oasis.x, oasis.z)).is_greater(SETTINGS.sea_level)
	assert_int(checked).is_greater(0)  # some cells were dealt one on a mesa, and kept dry
	var bowl_bound := absf(SETTINGS.sea_level - SETTINGS.oasis_depth - SETTINGS.base_height)
	var flat: TerrainSettings = SETTINGS.duplicate()
	flat.oasis_depth = SETTINGS.oasis_depth + 3.0
	(
		assert_float(HeightSampler.new(flat, SEEDS[0]).max_deviation() - sampler.max_deviation())
		. is_equal_approx(
			absf(SETTINGS.sea_level - flat.oasis_depth - SETTINGS.base_height) - bowl_bound, 1e-4
		)
	)


func test_inside_the_bowl_no_cliff_and_the_shore_is_not_a_circle() -> void:
	var climb := 4.0 * tan(deg_to_rad(FOX.max_slope_degrees))
	for seed_value in SEEDS:
		var sampler := HeightSampler.new(SETTINGS, seed_value)
		for centre in _full_oases(sampler):
			var shores := PackedFloat32Array()
			for side in 16:
				var ray := Vector2.from_angle(side * TAU / 16.0)
				var previous := sampler.height_at(centre.x, centre.y)
				var shore := -1.0
				for step in range(1, int(SETTINGS.oasis_radius * 0.7 / 4.0) + 1):
					var p := centre + ray * step * 4.0
					var h := sampler.height_at(p.x, p.y)
					(
						assert_float(absf(h - previous))
						. override_failure_message(str(centre))
						. is_less_equal(climb)
					)
					if shore < 0.0 and h >= SETTINGS.sea_level:
						shore = step * 4.0
					previous = h
				shores.append(shore)
			var low := Array(shores).min() as float
			var high := Array(shores).max() as float
			assert_float(high - low).is_greater_equal(4.0)  # lobed, not round
