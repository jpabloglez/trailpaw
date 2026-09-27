## Tests for [ChunkGenerator]: determinism, seam-free borders, topology and threading.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const SEED: int = 12345

var _settings: TerrainSettings


func before() -> void:
	_settings = load(SETTINGS_PATH)


func _gen(coord: Vector2i, lod: int = 0, world_seed: int = SEED) -> ChunkData:
	return ChunkGenerator.generate(coord, lod, _settings, world_seed)


## World-space position of vertex (i, j) of [param data].
func _world(data: ChunkData, i: int, j: int) -> Vector3:
	var v := data.vertices[j * data.resolution + i]
	return v + Vector3(data.coord.x, 0.0, data.coord.y) * _settings.chunk_size


# --- determinism ----------------------------------------------------------------------


func test_same_seed_gives_identical_chunk_hash() -> void:
	assert_str(_gen(Vector2i(3, -2)).content_hash()).is_equal(_gen(Vector2i(3, -2)).content_hash())


func test_different_seed_or_coord_changes_hash() -> void:
	var base := _gen(Vector2i(3, -2)).content_hash()
	assert_str(_gen(Vector2i(3, -2), 0, SEED + 1).content_hash()).is_not_equal(base)
	assert_str(_gen(Vector2i(4, -2)).content_hash()).is_not_equal(base)


func test_worker_thread_generation_matches_main_thread() -> void:
	var holder: Array[ChunkData] = []
	var settings_copy := _settings.duplicate() as TerrainSettings
	var task := WorkerThreadPool.add_task(
		func() -> void:
			holder.append(ChunkGenerator.generate(Vector2i(-7, 5), 0, settings_copy, SEED))
	)
	WorkerThreadPool.wait_for_task_completion(task)
	assert_str(holder[0].content_hash()).is_equal(_gen(Vector2i(-7, 5)).content_hash())


# --- seams ----------------------------------------------------------------------------


func _assert_x_border_matches(left: ChunkData, right: ChunkData) -> void:
	var last := left.resolution - 1
	for j in left.resolution:
		assert_vector(_world(left, last, j)).is_equal(_world(right, 0, j))
		assert_vector(left.normals[j * left.resolution + last]).is_equal(
			right.normals[j * right.resolution]
		)


func _assert_z_border_matches(near: ChunkData, far: ChunkData) -> void:
	var last := near.resolution - 1
	for i in near.resolution:
		assert_vector(_world(near, i, last)).is_equal(_world(far, i, 0))
		assert_vector(near.normals[last * near.resolution + i]).is_equal(far.normals[i])


func test_neighbour_edges_match_along_x() -> void:
	_assert_x_border_matches(_gen(Vector2i(0, 0)), _gen(Vector2i(1, 0)))


func test_neighbour_edges_match_along_z() -> void:
	_assert_z_border_matches(_gen(Vector2i(0, 0)), _gen(Vector2i(0, 1)))


func test_neighbour_edges_match_at_negative_coords() -> void:
	_assert_x_border_matches(_gen(Vector2i(-2, -3)), _gen(Vector2i(-1, -3)))
	_assert_z_border_matches(_gen(Vector2i(-2, -3)), _gen(Vector2i(-2, -2)))


func test_neighbour_edges_match_far_from_origin() -> void:
	_assert_x_border_matches(_gen(Vector2i(156, 3)), _gen(Vector2i(157, 3)))


func test_coarse_lod_vertices_lie_on_fine_lod_heights() -> void:
	var fine := _gen(Vector2i(2, 1), 0)
	var coarse := _gen(Vector2i(2, 1), 1)
	var ratio := (fine.resolution - 1) / (coarse.resolution - 1)
	for j in coarse.resolution:
		for i in coarse.resolution:
			assert_vector(_world(coarse, i, j)).is_equal(_world(fine, i * ratio, j * ratio))


# --- topology -------------------------------------------------------------------------


func test_counts_per_lod() -> void:
	for lod in _settings.lod_resolutions.size():
		var data := _gen(Vector2i.ZERO, lod)
		var res := _settings.resolution_for_lod(lod)
		assert_int(data.vertices.size()).is_equal(res * res)
		assert_int(data.normals.size()).is_equal(res * res)
		assert_int(data.uvs.size()).is_equal(res * res)
		assert_int(data.indices.size()).is_equal((res - 1) * (res - 1) * 6)


func test_vertices_span_the_chunk() -> void:
	var data := _gen(Vector2i(5, 5))
	var last := data.vertices[data.vertices.size() - 1]
	assert_float(data.vertices[0].x).is_equal(0.0)
	assert_float(last.x).is_equal(_settings.chunk_size)
	assert_float(last.z).is_equal(_settings.chunk_size)


func test_triangles_face_up_by_godot_winding() -> void:
	var data := _gen(Vector2i(1, 1), 1)
	# Let Godot compute face normals from our winding; they must point upwards.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in data.vertices:
		st.add_vertex(v)
	for index: int in data.indices:
		st.add_index(index)
	st.generate_normals()
	var generated: PackedVector3Array = st.commit_to_arrays()[Mesh.ARRAY_NORMAL]
	for n: Vector3 in generated:
		assert_float(n.y).is_greater(0.0)


func test_normals_are_unit_and_upward() -> void:
	for n: Vector3 in _gen(Vector2i(-4, 9)).normals:
		assert_float(n.length()).is_equal_approx(1.0, 1e-5)
		assert_float(n.y).is_greater(0.0)


func test_collision_heights_only_for_lod0_and_match_sampler() -> void:
	var data := _gen(Vector2i(2, -1), 0)
	var sampler := HeightSampler.new(_settings, SEED)
	assert_int(data.collision_heights.size()).is_equal(data.resolution * data.resolution)
	for p: Vector2i in [Vector2i(0, 0), Vector2i(10, 33), Vector2i(64, 64)]:
		var world := _world(data, p.x, p.y)
		var expected := sampler.height_at(world.x, world.z)
		var actual := data.collision_heights[p.y * data.resolution + p.x]
		assert_float(actual).is_equal_approx(expected, 1e-4)
	assert_int(_gen(Vector2i(2, -1), 1).collision_heights.size()).is_equal(0)
