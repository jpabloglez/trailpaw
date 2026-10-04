## Tests for [BiomeResolver]: weights sum to 1, band order along any direction,
## continuous transitions, cycling and blended values.
extends GdUnitTestSuite

const TABLE_PATH: String = "res://data/biomes/biome_table.tres"
const SEED: int = 12345
const ORDER: Array[StringName] = [&"meadow", &"forest", &"river_valley", &"wetland", &"hills"]

var _table: BiomeTable
var _resolver: BiomeResolver


func before() -> void:
	_table = load(TABLE_PATH)
	_resolver = BiomeResolver.new(_table, SEED)


func _ray_point(angle: float, distance: float) -> Vector2:
	return _table.spawn + Vector2.from_angle(angle) * distance


func test_weights_sum_to_one_and_are_non_negative() -> void:
	for i in 41:
		for j in 41:
			var x := -20000.0 + i * 1000.0 + j * 7.3
			var z := -20000.0 + j * 1000.0 + i * 3.1
			var total := 0.0
			for w: float in _resolver.weights_at(x, z).values():
				assert_float(w).is_greater_equal(0.0)
				total += w
			assert_float(total).is_equal_approx(1.0, 1e-6)


func test_spawn_is_pure_meadow() -> void:
	var weights := _resolver.weights_at(_table.spawn.x, _table.spawn.y)
	assert_dict(weights).is_equal({&"meadow": 1.0})


func test_bands_appear_in_configured_order_along_any_direction() -> void:
	var expected: Array[StringName] = []
	expected.assign(ORDER + ORDER + [ORDER[0]])  # two full cycles and a bit
	for a in 8:
		var angle := a * TAU / 8.0 + 0.1
		var seen: Array[StringName] = []
		var d := 0.0
		while d < 2.0 * _table.sequence_length() + 400.0:
			var p := _ray_point(angle, d)
			var id := _resolver.dominant_at(p.x, p.y).id
			if seen.is_empty() or seen[-1] != id:
				seen.append(id)
			d += 5.0
		assert_array(seen).override_failure_message("angle %.2f: %s" % [angle, seen]).is_equal(
			expected
		)


func test_transitions_are_continuous() -> void:
	# Max slope of the cross-fade: 1.5 / blend per metre of noisy distance, and the noisy
	# distance changes by at most 1 + A·f·NOISE_GRADIENT_FACTOR per metre walked.
	var noise_slope := (
		_table.boundary_noise_amplitude
		* _table.boundary_noise_frequency
		* BiomeTable.NOISE_GRADIENT_FACTOR
	)
	var limit := 1.5 / _table.blend_width * (1.0 + noise_slope) + 1e-3
	for a in 4:
		var angle := a * TAU / 4.0 + 0.37
		var previous := _resolver.weights_at(_ray_point(angle, 0.0).x, _ray_point(angle, 0.0).y)
		for step in range(1, 3600):
			var p := _ray_point(angle, float(step))
			var current := _resolver.weights_at(p.x, p.y)
			for id: StringName in ORDER:
				var jump := absf(current.get(id, 0.0) - previous.get(id, 0.0))
				if jump > limit:
					fail("angle %.2f d=%d: %s jumped %.4f" % [angle, step, id, jump])
					return
			previous = current


func test_boundaries_are_noisy_not_perfect_circles() -> void:
	# Where the first boundary is crossed differs between directions.
	var crossings: Array[float] = []
	for a in 12:
		var d := 0.0
		while (
			(
				_resolver
				. dominant_at(_ray_point(a * TAU / 12.0, d).x, _ray_point(a * TAU / 12.0, d).y)
				. id
			)
			== &"meadow"
		):
			d += 2.0
		crossings.append(d)
	assert_float(crossings.max() - crossings.min()).is_greater(30.0)
	assert_float(crossings.max() - crossings.min()).is_less(
		2.0 * _table.boundary_noise_amplitude + 10.0
	)


func test_band_centres_are_pure_and_cycle_repeats() -> void:
	var half := _table.biomes[0].band_width * 0.5
	for k in 8:
		var centre := _resolver.band_start(k) + half
		# Find a point whose noisy distance is the band centre: walk the +X ray.
		var d := centre - 200.0
		while _resolver.effective_distance(_table.spawn.x + d, _table.spawn.y) < centre:
			d += 1.0
		var weights := _resolver.weights_at(_table.spawn.x + d, _table.spawn.y)
		assert_dict(weights).is_equal({ORDER[k % ORDER.size()]: 1.0})


func test_non_cycling_table_keeps_the_last_biome_forever() -> void:
	var table := _table.duplicate() as BiomeTable
	table.cycle = false
	var resolver := BiomeResolver.new(table, SEED)
	assert_str(String(resolver.dominant_at(50000.0, 0.0).id)).is_equal("hills")


func test_same_seed_is_deterministic_and_seed_moves_boundaries() -> void:
	var again := BiomeResolver.new(_table, SEED)
	var other := BiomeResolver.new(_table, SEED + 1)
	var differs := false
	for i in 200:
		var x := 700.0 + i * 3.0
		assert_float(again.effective_distance(x, 11.0)).is_equal(
			_resolver.effective_distance(x, 11.0)
		)
		if not is_equal_approx(
			other.effective_distance(x, 11.0), _resolver.effective_distance(x, 11.0)
		):
			differs = true
	assert_bool(differs).is_true()


func test_blend_values_follow_the_weights() -> void:
	var blend := BiomeBlend.new()
	var biomes := {}
	for biome in _table.biomes:
		biomes[biome.id] = biome
	for i in 400:
		var x := 780.0 + i * 1.0
		_resolver.blend_into(x, 0.0, blend)
		var weights := _resolver.weights_at(x, 0.0)
		var offset := 0.0
		var ridged := 0.0
		for id: StringName in weights:
			offset += weights[id] * biomes[id].height_offset
			ridged += weights[id] * biomes[id].ridged_scale
		assert_float(blend.height_offset).is_equal_approx(offset, 1e-5)
		assert_float(blend.ridged_scale).is_equal_approx(ridged, 1e-5)
		assert_float(blend.secondary_weight).is_between(0.0, 0.5)


func test_steep_boundary_noise_is_rejected() -> void:
	var table := _table.duplicate() as BiomeTable
	table.boundary_noise_frequency = 0.01  # 110 m × 0.01 = 1.1 > MAX_NOISE_SLOPE
	assert_bool(table.is_valid()).is_false()
