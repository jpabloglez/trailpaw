## Tests for biome colours in [ChunkData] and the uniform-band fast path of [ChunkGenerator].
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const SEED: int = 12345

var _settings: TerrainSettings


func before() -> void:
	_settings = load(SETTINGS_PATH)


func _gen(coord: Vector2i, lod: int = 0) -> ChunkData:
	return ChunkGenerator.generate(coord, lod, _settings, SEED)


func _world(data: ChunkData, i: int, j: int) -> Vector3:
	var v := data.vertices[j * data.resolution + i]
	return v + Vector3(data.coord.x, 0.0, data.coord.y) * _settings.chunk_size


## Rounds to single precision, as vertex positions are stored.
func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


# --- biome colours --------------------------------------------------------------------


func test_vertex_colours_cover_surface_and_skirt() -> void:
	var data := _gen(Vector2i(4, -2), 0)
	assert_int(data.colors.size()).is_equal(data.vertices.size())
	assert_int(data.custom0.size()).is_equal(data.vertices.size() * 4)


func test_spawn_chunk_uses_the_meadow_palette() -> void:
	var meadow := _settings.biomes.biomes[0]
	var data := _gen(Vector2i(0, 0), 0)
	assert_object(data.colors[0]).is_equal(meadow.ground_color_a)
	assert_int(data.custom0[0]).is_equal(meadow.ground_color_b.r8)


func test_colours_match_across_chunk_borders() -> void:
	# Across a band boundary (chunk 12 ≈ 800 m out, inside the meadow→forest blend).
	var left := _gen(Vector2i(12, 0))
	var right := _gen(Vector2i(13, 0))
	var last := left.resolution - 1
	for j in left.resolution:
		assert_object(left.colors[j * left.resolution + last]).is_equal(
			right.colors[j * right.resolution]
		)


func test_uniform_band_fast_path_is_exact_and_seamless() -> void:
	# Chunk (9, 0) lies wholly inside one band (fast path); (10, 0) is near a boundary.
	var sampler := HeightSampler.new(_settings, SEED)
	var blend := BiomeBlend.new()
	var span := float(_settings.resolution_for_lod(0) + 1) * _settings.step_for_lod(0)
	(
		assert_bool(
			sampler.resolver().uniform_blend(9 * 64.0 + 32.0, 32.0, span * 0.5 * sqrt(2.0), blend)
		)
		. is_true()
	)
	(
		assert_bool(
			sampler.resolver().uniform_blend(10 * 64.0 + 32.0, 32.0, span * 0.5 * sqrt(2.0), blend)
		)
		. is_false()
	)
	var uniform := _gen(Vector2i(9, 0))
	for v in uniform.surface_vertex_count():
		var w := _world(uniform, v % uniform.resolution, v / uniform.resolution)
		# Bit-identical at the stored (single) precision.
		assert_float(w.y).is_equal(_f32(sampler.height_at(w.x, w.z)))
	var blended := _gen(Vector2i(10, 0))
	var last := uniform.resolution - 1
	for j in uniform.resolution:
		assert_vector(_world(uniform, last, j)).is_equal(_world(blended, 0, j))
		assert_vector(uniform.normals[j * uniform.resolution + last]).is_equal(
			blended.normals[j * blended.resolution]
		)
