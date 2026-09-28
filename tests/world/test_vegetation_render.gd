## Tests for vegetation rendering: library, MultiMesh buffer layout, counts and pooling.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const SEED: int = 12345
const MEADOW := Vector2i(3, 3)
const FOREST := Vector2i(17, 2)

var _settings: TerrainSettings
var _scatterer: VegetationScatterer
var _library: VegetationLibrary


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_scatterer = VegetationScatterer.new(_settings.biomes)
	_library = VegetationLibrary.new(_settings.biomes)


func _gen(coord: Vector2i, lod: int = 0) -> ChunkData:
	return ChunkGenerator.generate_with(
		coord, lod, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED
	)


func _make_chunk() -> TerrainChunk:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	return chunk


func test_library_knows_every_type_once_with_its_settings() -> void:
	assert_int(_library.ids().size()).is_equal(_scatterer.type_ids().size())
	assert_object(_library.mesh_for(&"tree_oak")).is_not_null()
	assert_float(_library.visibility_range(&"grass")).is_less(
		_library.visibility_range(&"tree_oak")
	)
	assert_bool(_library.casts_shadows(&"tree_oak")).is_true()
	assert_bool(_library.casts_shadows(&"grass")).is_false()


## Decodes instance [param i] of a buffer with the documented MultiMesh 3D layout
## (row-major 3×4: basis rows, each followed by one origin component).
func _decode(buffer: PackedFloat32Array, i: int) -> Transform3D:
	var o := i * VegetationScatterer.FLOATS_PER_INSTANCE
	var basis := Basis(
		Vector3(buffer[o], buffer[o + 4], buffer[o + 8]),
		Vector3(buffer[o + 1], buffer[o + 5], buffer[o + 9]),
		Vector3(buffer[o + 2], buffer[o + 6], buffer[o + 10])
	)
	return Transform3D(basis, Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11]))


func test_buffer_encodes_upright_scaled_instances() -> void:
	var data := _gen(FOREST)
	var type := load("res://data/vegetation/tree_detailed.tres") as VegetationType
	var buffer: PackedFloat32Array = data.vegetation[&"tree_detailed"]
	for i in data.vegetation_count(&"tree_detailed"):
		var t := _decode(buffer, i)
		assert_float(t.basis.get_scale().y).is_between(type.scale_min - 1e-3, type.scale_max + 1e-3)
		assert_vector(t.basis.y.normalized()).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-3)


func test_buffer_layout_matches_godot_instance_transforms() -> void:
	# The headless dummy renderer does not store MultiMesh data (it reads back identity), so
	# this cross-check only runs with a real renderer (e.g. locally with a GPU).
	if DisplayServer.get_name() == "headless":
		return
	var data := _gen(FOREST)
	var buffer: PackedFloat32Array = data.vegetation[&"tree_detailed"]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = data.vegetation_count(&"tree_detailed")
	multimesh.buffer = buffer
	for i in multimesh.instance_count:
		var got := multimesh.get_instance_transform(i)
		var expected := _decode(buffer, i)
		assert_vector(got.origin).is_equal_approx(expected.origin, Vector3.ONE * 1e-3)
		assert_vector(got.basis.x).is_equal_approx(expected.basis.x, Vector3.ONE * 1e-3)


func test_chunk_draws_one_multimesh_per_type_with_the_data_counts() -> void:
	var chunk := _make_chunk()
	var data := _gen(FOREST)
	chunk.apply(data, load(MATERIAL_PATH), _library)
	for id: StringName in data.vegetation:
		assert_int(chunk.vegetation_count(id)).is_equal(data.vegetation_count(id))
		var node := chunk.vegetation_node(id)
		assert_object(node.multimesh.mesh).is_same(_library.mesh_for(id))
		assert_float(node.visibility_range_end).is_equal(_library.visibility_range(id))


func test_reapplying_reuses_nodes_and_hides_missing_types() -> void:
	var chunk := _make_chunk()
	chunk.apply(_gen(FOREST), load(MATERIAL_PATH), _library)
	chunk.apply(_gen(MEADOW), load(MATERIAL_PATH), _library)
	var nodes_after_two := chunk.get_child_count()
	chunk.apply(_gen(FOREST), load(MATERIAL_PATH), _library)
	chunk.apply(_gen(MEADOW), load(MATERIAL_PATH), _library)
	assert_int(chunk.get_child_count()).is_equal(nodes_after_two)  # pooled, no leak
	assert_int(chunk.vegetation_count(&"tree_detailed")).is_equal(0)  # forest-only type hidden
	assert_int(chunk.vegetation_count(&"flower_yellowA")).is_greater(0)


func test_reset_hides_vegetation_and_no_library_means_none() -> void:
	var chunk := _make_chunk()
	chunk.apply(_gen(MEADOW), load(MATERIAL_PATH), _library)
	chunk.reset()
	assert_int(chunk.vegetation_count(&"grass")).is_equal(0)
	chunk.apply(_gen(MEADOW), load(MATERIAL_PATH))
	assert_int(chunk.vegetation_count(&"grass")).is_equal(0)


func test_streamer_renders_vegetation() -> void:
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	var streamer: WorldStreamer = auto_free(WorldStreamer.new())
	streamer.terrain = _settings
	var streaming := StreamingSettings.new()
	streaming.load_radius = 1
	streaming.unload_radius = 2
	streaming.lod0_radius = 1.5
	streaming.build_budget_ms = 8.0
	streaming.max_tasks_in_flight = 4
	streaming.rebase_distance = 2000.0
	streamer.streaming = streaming
	streamer.chunk_scene = load(CHUNK_SCENE)
	streamer.material = load(MATERIAL_PATH)
	streamer.target = target
	GameState.world_seed = SEED
	add_child(streamer)
	for i in 600:
		await get_tree().process_frame
		if streamer.is_idle():
			break
	assert_int(streamer.get_chunk(Vector2i.ZERO).vegetation_count(&"grass")).is_greater(50)
	GameState.world_seed = 0
