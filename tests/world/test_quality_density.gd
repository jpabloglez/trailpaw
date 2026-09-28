## Tests for quality presets scaling vegetation density, and streamer regeneration on change.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const SEED: int = 12345
const MEADOW := Vector2i(3, 3)

var _settings: TerrainSettings
var _scatterer: VegetationScatterer


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_scatterer = VegetationScatterer.new(_settings.biomes)


func after_test() -> void:
	Settings.set_quality(load(Settings.DEFAULT_QUALITY_PATH))
	GameState.world_seed = 0


func _preset(id: String) -> QualityPreset:
	return load("res://data/quality/%s.tres" % id)


func _grass(density: float) -> int:
	var data := ChunkGenerator.generate_with(
		MEADOW, 0, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED, density
	)
	return data.vegetation_count(&"grass")


func test_presets_follow_the_architecture_table() -> void:
	assert_float(_preset("low").vegetation_density).is_equal(0.4)
	assert_float(_preset("medium").vegetation_density).is_equal(0.7)
	assert_float(_preset("high").vegetation_density).is_equal(1.0)
	for id: String in ["low", "medium", "high"]:
		assert_array(Array(_preset(id).get_validation_errors())).is_empty()


func test_instance_count_scales_with_the_preset() -> void:
	var low := _grass(_preset("low").vegetation_density)
	var medium := _grass(_preset("medium").vegetation_density)
	var high := _grass(_preset("high").vegetation_density)
	assert_int(low).is_less(medium)
	assert_int(medium).is_less(high)
	assert_float(float(low) / high).is_between(0.25, 0.55)
	assert_float(float(medium) / high).is_between(0.55, 0.85)


func test_streamer_regenerates_on_quality_change_without_gaps() -> void:
	GameState.world_seed = SEED
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	var streaming := StreamingSettings.new()
	streaming.load_radius = 1
	streaming.unload_radius = 2
	streaming.lod0_radius = 1.5
	streaming.build_budget_ms = 8.0
	streaming.max_tasks_in_flight = 4
	streaming.rebase_distance = 2000.0
	var streamer: WorldStreamer = auto_free(WorldStreamer.new())
	streamer.terrain = _settings
	streamer.streaming = streaming
	streamer.chunk_scene = load("res://scenes/world/terrain_chunk.tscn")
	streamer.material = load("res://data/world/terrain_material.tres")
	streamer.target = target
	add_child(streamer)
	for i in 600:
		await get_tree().process_frame
		if streamer.is_idle():
			break
	assert_float(streamer.vegetation_density).is_equal(Settings.quality.vegetation_density)
	var before_count := streamer.get_chunk(Vector2i.ZERO).vegetation_count(&"grass")
	var built: int = streamer.stats()["total_built"]
	Settings.set_quality(_preset("low"))
	assert_float(streamer.vegetation_density).is_equal(0.4)
	for i in 600:
		await get_tree().process_frame
		for coord: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, -1)]:
			assert_bool(streamer.is_loaded(coord)).is_true()  # never a gap while regenerating
		if streamer.is_idle():
			break
	assert_int(streamer.stats()["total_built"]).is_greater(built)
	assert_int(streamer.get_chunk(Vector2i.ZERO).vegetation_count(&"grass")).is_less(before_count)
