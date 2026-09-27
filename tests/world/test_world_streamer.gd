## Integration tests for [WorldStreamer] with real worker threads and small radii.
extends GdUnitTestSuite

const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const TERRAIN_PATH: String = "res://data/world/terrain_settings.tres"
const MAX_FRAMES: int = 1200

var _streamer: WorldStreamer
var _target: Node3D
var _settings: StreamingSettings
var _chunk_size: float


func before_test() -> void:
	_settings = StreamingSettings.new()
	_settings.load_radius = 2
	_settings.unload_radius = 3
	_settings.build_budget_ms = 8.0
	_settings.max_tasks_in_flight = 4
	_settings.lod0_radius = 1.5
	_settings.rebase_distance = 2000.0
	_target = auto_free(Node3D.new())
	add_child(_target)
	_streamer = _make_streamer(_settings)


func _make_streamer(settings: StreamingSettings) -> WorldStreamer:
	var streamer: WorldStreamer = auto_free(WorldStreamer.new())
	streamer.terrain = load(TERRAIN_PATH)
	streamer.streaming = settings
	streamer.chunk_scene = load(CHUNK_SCENE)
	streamer.material = StandardMaterial3D.new()
	streamer.target = _target
	add_child(streamer)
	_chunk_size = streamer.terrain.chunk_size
	return streamer


func _until_idle(streamer: WorldStreamer = _streamer) -> void:
	for i in MAX_FRAMES:
		await get_tree().process_frame
		if streamer.is_idle():
			return
	fail("streamer did not become idle")


func _move_to_chunk(coord: Vector2i) -> void:
	_target.position = Vector3(coord.x + 0.5, 0.0, coord.y + 0.5) * _chunk_size


func _sorted(coords: Array) -> Array:
	var copy := coords.duplicate()
	copy.sort()
	return copy


func test_loads_exactly_the_desired_set() -> void:
	await _until_idle()
	var expected := StreamingPlan.desired_chunks(Vector2i.ZERO, _settings).keys()
	assert_array(_sorted(_streamer.loaded_coords())).is_equal(_sorted(expected))


func test_chunks_are_positioned_at_their_coordinates() -> void:
	await _until_idle()
	var chunk := _streamer.get_chunk(Vector2i(1, -1))
	assert_vector(chunk.position).is_equal(Vector3(_chunk_size, 0.0, -_chunk_size))
	assert_bool(chunk.has_collision()).is_true()


func test_moving_one_chunk_loads_the_new_edge_and_keeps_hysteresis_band() -> void:
	await _until_idle()
	var before := _streamer.loaded_coords()
	_move_to_chunk(Vector2i(1, 0))
	await _until_idle()
	var center := Vector2i(1, 0)
	for coord: Vector2i in StreamingPlan.desired_chunks(center, _settings):
		assert_bool(_streamer.is_loaded(coord)).is_true()
	for coord: Vector2i in _streamer.loaded_coords():
		assert_bool(StreamingPlan.should_unload(coord, center, _settings)).is_false()
	# (-2, 0) is now 3 chunks away: outside load_radius but inside unload_radius → kept.
	assert_bool(before.has(Vector2i(-2, 0))).is_true()
	assert_bool(_streamer.is_loaded(Vector2i(-2, 0))).is_true()


func test_far_jump_unloads_everything_old_and_reuses_pooled_nodes() -> void:
	await _until_idle()
	var built_before: int = _streamer.stats()["total_built"]
	_move_to_chunk(Vector2i(40, 40))
	await _until_idle()
	for coord: Vector2i in _streamer.loaded_coords():
		assert_float(StreamingPlan.chunk_distance(coord, Vector2i(40, 40))).is_less_equal(2.0)
	assert_int(_streamer.stats()["total_built"]).is_equal(built_before * 2)
	var node_count := _streamer.get_child_count()
	assert_int(node_count).is_equal(StreamingPlan.desired_chunks(Vector2i.ZERO, _settings).size())


func test_stale_results_are_discarded() -> void:
	# Leave while the first chunks are still generating.
	await get_tree().process_frame
	_move_to_chunk(Vector2i(-30, 12))
	await _until_idle()
	for coord: Vector2i in _streamer.loaded_coords():
		assert_float(StreamingPlan.chunk_distance(coord, Vector2i(-30, 12))).is_less_equal(2.0)


func test_tiny_budget_builds_at_most_one_chunk_per_frame() -> void:
	_streamer.queue_free()
	var slow := _settings.duplicate() as StreamingSettings
	slow.build_budget_ms = 0.0001
	var streamer := _make_streamer(slow)
	var max_per_frame := 0
	for i in MAX_FRAMES:
		await get_tree().process_frame
		max_per_frame = maxi(max_per_frame, streamer.stats()["last_frame_built"])
		if streamer.is_idle():
			break
	assert_int(max_per_frame).is_equal(1)
	assert_int(streamer.loaded_coords().size()).is_equal(13)


func test_is_ready_at_reports_collision_under_position() -> void:
	assert_bool(_streamer.is_ready_at(Vector3(10.0, 0.0, 10.0))).is_false()
	await _until_idle()
	assert_bool(_streamer.is_ready_at(Vector3(10.0, 0.0, 10.0))).is_true()
	assert_bool(_streamer.is_ready_at(Vector3(10.0 * _chunk_size, 0.0, 0.0))).is_false()


func test_freeing_mid_load_waits_for_tasks() -> void:
	await get_tree().process_frame
	assert_int(_streamer.stats()["in_flight"]).is_greater(0)
	_streamer.free()
	await get_tree().process_frame
	# Reaching here without engine errors means every task was waited on.
	assert_bool(true).is_true()


func test_loaded_lods_match_the_plan_and_only_lod0_collides() -> void:
	await _until_idle()
	var desired := StreamingPlan.desired_chunks(Vector2i.ZERO, _settings)
	for coord: Vector2i in desired:
		var chunk := _streamer.get_chunk(coord)
		assert_int(chunk.lod).is_equal(desired[coord])
		assert_bool(chunk.has_collision()).is_equal(chunk.lod == 0)


func test_no_chunk_disappears_while_walking_across_chunks() -> void:
	await _until_idle()
	var step := _chunk_size / 20.0
	var path_frames := 0
	# Walk 3 chunks along +X and 1 diagonally; check every frame.
	while _target.position.x < 3.5 * _chunk_size:
		var before := _streamer.loaded_coords()
		_target.position += Vector3(step, 0.0, step * 0.3)
		await get_tree().process_frame
		path_frames += 1
		(
			assert_bool(_streamer.is_ready_at(_target.position))
			. override_failure_message("no collision under target at frame %d" % path_frames)
			. is_true()
		)
		var center := StreamingPlan.chunk_at(_target.position.x, _target.position.z, _chunk_size)
		for coord: Vector2i in before:
			if not StreamingPlan.should_unload(coord, center, _settings):
				assert_bool(_streamer.is_loaded(coord)).is_true()
	await _until_idle()
	var center := StreamingPlan.chunk_at(_target.position.x, _target.position.z, _chunk_size)
	var desired := StreamingPlan.desired_chunks(center, _settings)
	for coord: Vector2i in desired:
		if desired[coord] == 0:
			assert_int(_streamer.get_chunk(coord).lod).is_equal(0)


func test_rebase_keeps_chunks_at_their_absolute_positions_without_reloading() -> void:
	FloatingOrigin.reset()
	FloatingOrigin.configure(_chunk_size, 0.0)  # manual rebases only
	FloatingOrigin.track(_target)
	_target.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	_move_to_chunk(Vector2i(3, -2))
	await _until_idle()
	var coords := _sorted(_streamer.loaded_coords())
	var built: int = _streamer.stats()["total_built"]
	FloatingOrigin.rebase_now()
	await get_tree().process_frame
	assert_object(GameState.origin_chunk).is_equal(Vector2i(4, -2))
	assert_array(_sorted(_streamer.loaded_coords())).is_equal(coords)
	assert_int(_streamer.stats()["total_built"]).is_equal(built)
	for coord: Vector2i in _streamer.loaded_coords():
		var absolute: Vector3 = GameState.absolute_position(_streamer.get_chunk(coord).position)
		assert_vector(absolute).is_equal(Vector3(coord.x, 0.0, coord.y) * _chunk_size)
	assert_bool(_streamer.is_ready_at(_target.position)).is_true()
	FloatingOrigin.reset()
	GameState.chunk_size = 0.0


func test_emits_chunks_changed_and_debug_lines() -> void:
	var monitor := monitor_signals(_streamer)
	await _until_idle()
	await assert_signal(monitor).is_emitted("chunks_changed")
	var lines := _streamer.get_debug_lines()
	assert_str(lines[0]).contains("%d loaded" % _streamer.loaded_coords().size())
	assert_float(_streamer.stats()["max_chunk_ms"]).is_greater(0.0)
