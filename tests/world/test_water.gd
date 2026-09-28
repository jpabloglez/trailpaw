## Tests for water v1: water planes in chunks with ground below sea level.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const SEED: int = 12345

var _settings: TerrainSettings


func before() -> void:
	_settings = load(SETTINGS_PATH)


func after_test() -> void:
	FloatingOrigin.reset()
	GameState.chunk_size = 0.0


## First chunk along +X (from [param start_x] m) whose data has water, at LOD [param lod].
func _find_wet_coord(start_x: float, lod: int = 1) -> Vector2i:
	var size := _settings.chunk_size
	for i in 60:
		var coord := Vector2i(floori(start_x / size) + i, 0)
		if ChunkGenerator.generate(coord, lod, _settings, SEED).has_water():
			return coord
	return Vector2i(-99999, 0)


func _make_chunk(coord: Vector2i, lod: int = 0) -> TerrainChunk:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	chunk.position = Vector3(coord.x, 0.0, coord.y) * _settings.chunk_size
	chunk.apply(ChunkGenerator.generate(coord, lod, _settings, SEED), load(MATERIAL_PATH))
	return chunk


func test_spawn_is_dry_land() -> void:
	var sampler := HeightSampler.new(_settings, SEED)
	var spawn := _settings.biomes.spawn
	assert_float(sampler.height_at(spawn.x, spawn.y)).is_greater(_settings.sea_level + 2.0)
	assert_bool(_make_chunk(Vector2i.ZERO).has_water()).is_false()


func test_chunk_below_sea_level_shows_water_at_sea_level() -> void:
	var coord := _find_wet_coord(1700.0)  # river valley band starts ≈ 1600 m out
	assert_int(coord.x).is_greater(-99999)
	var chunk := _make_chunk(coord)
	assert_bool(chunk.has_water()).is_true()
	var water := chunk.get_node("%Water") as MeshInstance3D
	var size := _settings.chunk_size
	var centre := Vector3((coord.x + 0.5) * size, _settings.sea_level, (coord.y + 0.5) * size)
	assert_vector(water.global_position).is_equal_approx(centre, Vector3.ONE * 1e-3)
	assert_vector(water.scale).is_equal(Vector3(size, 1.0, size))


func test_water_plane_mesh_is_shared_between_chunks() -> void:
	var a := _make_chunk(Vector2i.ZERO).get_node("%Water") as MeshInstance3D
	var b := _make_chunk(Vector2i(1, 0)).get_node("%Water") as MeshInstance3D
	assert_object(a.mesh).is_same(b.mesh)


func test_reset_hides_water() -> void:
	var chunk := _make_chunk(_find_wet_coord(1700.0))
	chunk.reset()
	assert_bool(chunk.has_water()).is_false()


func test_river_valley_has_more_water_than_meadow() -> void:
	var resolver := HeightSampler.new(_settings, SEED).resolver()
	var coverage := {}
	for b in [0, 2]:  # meadow, river valley
		var wet := 0
		var total := 0
		for a in 16:
			var p := Vector2.from_angle(a * TAU / 16.0) * (resolver.band_start(b) + 400.0)
			var coord := StreamingPlan.chunk_at(p.x, p.y, _settings.chunk_size)
			if ChunkGenerator.generate(coord, 1, _settings, SEED).has_water():
				wet += 1
			total += 1
		coverage[b] = float(wet) / total
	assert_float(coverage[2]).is_greater(coverage[0] + 0.25)


func test_water_stays_at_absolute_sea_level_after_rebase() -> void:
	var coord := _find_wet_coord(1700.0)
	var streamer_chunk := _make_chunk(coord)
	streamer_chunk.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)  # stands in for the streamer
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	target.position = streamer_chunk.position
	target.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	FloatingOrigin.configure(_settings.chunk_size, 0.0)
	FloatingOrigin.track(target)
	var water := streamer_chunk.get_node("%Water") as MeshInstance3D
	var before: Vector3 = GameState.absolute_position(water.global_position)
	FloatingOrigin.rebase_now()
	assert_object(GameState.origin_chunk).is_not_equal(Vector2i.ZERO)
	assert_vector(GameState.absolute_position(water.global_position)).is_equal_approx(
		before, Vector3.ONE * 1e-3
	)
	assert_float(water.global_position.y).is_equal(_settings.sea_level)


func test_valley_has_several_moderate_lakes_not_one_sheet() -> void:
	var sampler := HeightSampler.new(_settings, SEED)
	var resolver := sampler.resolver()
	var wet := 0
	var total := 0
	var lakes := 0
	for a in 24:
		var direction := Vector2.from_angle(a * TAU / 24.0)
		var was_wet := false
		var d := resolver.band_start(2) + 150.0
		while d < resolver.band_start(3) - 150.0:
			var p := direction * d
			var is_wet := sampler.height_at(p.x, p.y) < _settings.sea_level
			if is_wet and not was_wet:
				lakes += 1
			was_wet = is_wet
			wet += int(is_wet)
			total += 1
			d += 4.0
	var coverage := float(wet) / total
	assert_float(coverage).is_between(0.1, 0.35)
	assert_float(float(lakes) / 24.0).is_greater(1.5)  # separate lakes per 500 m line


func test_water_level_is_published_to_shaders() -> void:
	var entry: Dictionary = ProjectSettings.get_setting("shader_globals/water_level")
	assert_str(entry["type"]).is_equal("float")
	var code := (load("res://shaders/terrain.gdshader") as Shader).code
	assert_str(code).contains("global uniform float water_level")
	assert_str(code).contains("shore_color")
	assert_str(code).contains("underwater_color")


func test_shore_and_underwater_tunables_are_in_the_materials() -> void:
	var terrain := load("res://data/world/terrain_material.tres") as ShaderMaterial
	for param: String in ["shore_color", "shore_height", "underwater_color", "underwater_depth"]:
		(
			assert_bool(terrain.get_shader_parameter(param) != null)
			. override_failure_message("%s missing from terrain material" % param)
			. is_true()
		)
	var water := load("res://data/world/water_material.tres") as ShaderMaterial
	var grazing: float = water.get_shader_parameter("grazing_opacity")
	assert_float(grazing).is_less(1.0)  # shallow beds must show through
