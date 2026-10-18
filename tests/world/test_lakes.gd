## Tests for the lake band (Phase 19, ADR-010): an alpine lake district between the hills and
## the mountains, mostly deep clear water with islands, crossable by swimming, whose water
## alone looks clear (per-chunk instance uniforms on the water plane).
extends GdUnitTestSuite

const Places := preload("res://tests/world/places.gd")
const GridWalk := preload("res://tests/world/grid_walk.gd")
const SETTINGS: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const SEEDS: Array[int] = [12345, 777, 2024]
const FOX: AnimalSpecies = preload("res://data/species/fox.tres")

var _lakes: BiomeDefinition


func before() -> void:
	for biome in SETTINGS.biomes.biomes:
		if biome.id == &"lakes":
			_lakes = biome


func test_the_lakes_lie_between_the_hills_and_the_mountains() -> void:
	var ids: Array[StringName] = []
	for biome in SETTINGS.biomes.biomes:
		ids.append(biome.id)
	var at := ids.find(&"lakes")
	assert_int(at).is_greater(0)
	assert_str(String(ids[at - 1])).is_equal("hills")
	assert_str(String(ids[at + 1])).is_equal("mountains")
	assert_float(_lakes.warmth).is_less(0.0)  # fresh, alpine


# Fractions of the lake band (sampled on rings) under water, deeply under it, and on islands.
func _stats(sampler: HeightSampler) -> Vector3:
	var water := SETTINGS.sea_level
	var start := Places.band_start(SETTINGS, sampler, &"lakes")
	var n := 0
	var wet := 0
	var deep := 0
	var isles := 0
	for a in 180:
		for i in 12:
			var p := (
				Vector2.from_angle(a * TAU / 180.0) * (start + (i + 0.5) / 12.0 * _lakes.band_width)
			)
			if sampler.resolver().dominant_at(p.x, p.y).id != &"lakes":
				continue
			n += 1
			var h := sampler.height_at(p.x, p.y)
			wet += int(h < water)
			deep += int(h < water - 2.0)
			isles += int(h > water + 0.5 and _ringed_by_water(sampler, p, 90.0))
	return Vector3(wet, deep, isles) / maxf(n, 1.0)


func _ringed_by_water(sampler: HeightSampler, p: Vector2, radius: float) -> bool:
	for d in 8:
		var q := p + Vector2.from_angle(d * TAU / 8.0) * radius
		if sampler.height_at(q.x, q.y) >= SETTINGS.sea_level:
			return false
	return true


func test_mostly_deep_water_with_islands_on_every_seed() -> void:
	for seed_value in SEEDS:
		var stats := _stats(HeightSampler.new(SETTINGS, seed_value))
		assert_float(stats.x).override_failure_message("water %s" % stats).is_between(0.5, 0.72)
		assert_float(stats.y / stats.x).is_greater(0.75)  # mostly deep, not a marsh
		assert_float(stats.z).override_failure_message("isles %s" % stats).is_greater(0.002)


func test_without_the_island_layer_there_are_far_fewer_islands() -> void:
	var flat: TerrainSettings = SETTINGS.duplicate()
	flat.island_amplitude = 0.0
	var with_isles := _stats(HeightSampler.new(SETTINGS, SEEDS[0])).z
	var without := _stats(HeightSampler.new(flat, SEEDS[0])).z
	assert_float(with_isles).is_greater(without * 2.0)


func test_the_band_can_be_crossed_by_swimming() -> void:
	for seed_value in SEEDS:
		var sampler := HeightSampler.new(SETTINGS, seed_value)
		var start := Places.band_start(SETTINGS, sampler, &"lakes")
		var rise := tan(deg_to_rad(FOX.max_slope_degrees)) * GridWalk.STEP
		for k in 4:
			var crossed := GridWalk.crosses(
				sampler,
				k * TAU / 4.0 + 0.4,
				start - 50.0,
				start + _lakes.band_width + 50.0,
				rise,
				SETTINGS.sea_level
			)
			(
				assert_bool(crossed)
				. override_failure_message("seed %d dir %d" % [seed_value, k])
				. is_true()
			)


func test_only_the_lakes_have_clear_water() -> void:
	assert_float(_lakes.water_clarity).is_greater(0.5)
	for biome in SETTINGS.biomes.biomes:
		if biome.id != &"lakes":
			assert_float(biome.water_clarity).is_equal(0.0)


func _chunk_at(sampler: HeightSampler, p: Vector2) -> ChunkData:
	var coord := Vector2i((p / SETTINGS.chunk_size).floor())
	var scatterer := VegetationScatterer.new(SETTINGS.biomes)
	return ChunkGenerator.generate_with(coord, 0, SETTINGS, sampler, scatterer, SEEDS[0])


# A lake-band point whose chunk holds water.
func _wet_lake_point(sampler: HeightSampler) -> Vector2:
	for a in 72:
		var p := Places.point_in(SETTINGS, sampler, &"lakes", 0.5, a * TAU / 72.0)
		if sampler.height_at(p.x, p.y) < SETTINGS.sea_level - 2.0:
			return p
	return Vector2.INF


func test_a_lake_chunk_hands_its_clear_water_to_the_water_plane() -> void:
	var sampler := HeightSampler.new(SETTINGS, SEEDS[0])
	var data := _chunk_at(sampler, _wet_lake_point(sampler))
	assert_bool(data.has_water()).is_true()
	assert_float(data.water_clarity).is_greater(0.5)
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	chunk.apply(data, load(MATERIAL_PATH), VegetationLibrary.new(SETTINGS.biomes))
	var water: MeshInstance3D = chunk.get_node("%Water")
	assert_bool(water.visible).is_true()
	assert_float(water.get_instance_shader_parameter(&"clarity")).is_equal(data.water_clarity)
	var tint: Vector3 = water.get_instance_shader_parameter(&"clear_tint")
	assert_float(tint.z).is_greater(tint.x)  # turquoise: more blue than red
	# The nearest lake to the spawn is in the meadow: its water keeps the usual murky look.
	var meadow := _chunk_at(sampler, Vector2(250.0, -720.0))
	assert_bool(meadow.has_water()).is_true()
	assert_float(meadow.water_clarity).is_equal(0.0)
