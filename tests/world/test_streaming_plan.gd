## Tests for [StreamingPlan]: chunk lookup, desired set, load order and hysteresis.
extends GdUnitTestSuite


func _settings(load_radius: int = 2, unload_radius: int = 3) -> StreamingSettings:
	var s := StreamingSettings.new()
	s.load_radius = load_radius
	s.unload_radius = unload_radius
	s.build_budget_ms = 2.0
	s.max_tasks_in_flight = 4
	s.lod0_radius = 1.5
	s.rebase_distance = 2000.0
	return s


func test_default_settings_are_valid() -> void:
	var s := load("res://data/world/streaming_settings.tres") as StreamingSettings
	assert_array(Array(s.get_validation_errors())).is_empty()


func test_unload_radius_must_exceed_load_radius() -> void:
	assert_bool(_settings(3, 3).is_valid()).is_false()


func test_chunk_at_floors_including_negatives() -> void:
	assert_object(StreamingPlan.chunk_at(0.0, 0.0, 64.0)).is_equal(Vector2i(0, 0))
	assert_object(StreamingPlan.chunk_at(63.99, 64.0, 64.0)).is_equal(Vector2i(0, 1))
	assert_object(StreamingPlan.chunk_at(-0.01, -64.0, 64.0)).is_equal(Vector2i(-1, -1))
	assert_object(StreamingPlan.chunk_at(-64.01, 10000.0, 64.0)).is_equal(Vector2i(-2, 156))


func test_desired_set_is_the_disc_of_load_radius() -> void:
	var center := Vector2i(10, -4)
	var desired := StreamingPlan.desired_chunks(center, _settings(2))
	# Lattice points with |offset| <= 2: 1 + 4 + 4 + 4 = 13.
	assert_int(desired.size()).is_equal(13)
	assert_bool(desired.has(center + Vector2i(2, 0))).is_true()
	assert_bool(desired.has(center + Vector2i(1, 1))).is_true()
	assert_bool(desired.has(center + Vector2i(2, 1))).is_false()
	for coord: Vector2i in desired:
		assert_float(StreamingPlan.chunk_distance(coord, center)).is_less_equal(2.0)


func test_unload_uses_hysteresis() -> void:
	var s := _settings(2, 3)
	var center := Vector2i.ZERO
	assert_bool(StreamingPlan.should_unload(Vector2i(3, 0), center, s)).is_false()
	assert_bool(StreamingPlan.should_unload(Vector2i(2, 2), center, s)).is_false()
	assert_bool(StreamingPlan.should_unload(Vector2i(3, 1), center, s)).is_true()


func test_load_order_is_nearest_first_with_view_tiebreak() -> void:
	var center := Vector2i.ZERO
	var coords: Array[Vector2i] = []
	coords.assign(StreamingPlan.desired_chunks(center, _settings(2)).keys())
	StreamingPlan.sort_by_priority(coords, center, Vector2.RIGHT)
	assert_object(coords[0]).is_equal(center)
	assert_object(coords[1]).is_equal(Vector2i(1, 0))  # ahead wins the first ring
	var last_distance := 0.0
	for coord: Vector2i in coords:
		var d := StreamingPlan.chunk_distance(coord, center)
		assert_float(d).is_greater_equal(last_distance - 1.0)  # bias never jumps a ring
		last_distance = maxf(last_distance, d)
	assert_int(coords.find(Vector2i(1, 0))).is_less(coords.find(Vector2i(-1, 0)))


func test_lod0_radius_must_cover_diagonals() -> void:
	var s := _settings()
	s.lod0_radius = 1.0
	assert_bool(s.is_valid()).is_false()


func test_lod_by_distance_with_hysteresis() -> void:
	var s := _settings(4, 5)
	assert_int(StreamingPlan.lod_for(0.0, -1, s)).is_equal(0)
	assert_int(StreamingPlan.lod_for(sqrt(2.0), -1, s)).is_equal(0)  # diagonal neighbour
	assert_int(StreamingPlan.lod_for(2.0, -1, s)).is_equal(StreamingPlan.FAR_LOD)
	assert_int(StreamingPlan.lod_for(2.0, 0, s)).is_equal(0)  # already detailed: keep
	assert_int(StreamingPlan.lod_for(2.6, 0, s)).is_equal(StreamingPlan.FAR_LOD)
	assert_int(StreamingPlan.lod_for(1.0, StreamingPlan.FAR_LOD, s)).is_equal(0)


func test_desired_set_assigns_lod0_to_the_3x3_block() -> void:
	var desired := StreamingPlan.desired_chunks(Vector2i.ZERO, _settings(4, 5))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			assert_int(desired[Vector2i(dx, dz)]).is_equal(0)
	assert_int(desired[Vector2i(2, 0)]).is_equal(StreamingPlan.FAR_LOD)
	assert_int(desired[Vector2i(4, 0)]).is_equal(StreamingPlan.FAR_LOD)
