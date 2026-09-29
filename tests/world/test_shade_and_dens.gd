## Tests for tree shade ([method TerrainChunk.is_shaded]) and den logs in the world data.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const SEED: int = 12345
const FOREST := Vector2i(17, 2)

var _settings: TerrainSettings
var _scatterer: VegetationScatterer
var _library: VegetationLibrary


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_scatterer = VegetationScatterer.new(_settings.biomes)
	_library = VegetationLibrary.new(_settings.biomes)


func _gen(coord: Vector2i) -> ChunkData:
	return ChunkGenerator.generate_with(
		coord, 0, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED
	)


func _chunk(data: ChunkData) -> TerrainChunk:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	var every_kind: Array[StringName] = []
	chunk.apply(data, load(MATERIAL_PATH), _library, every_kind)
	return chunk


func test_under_a_tree_is_shaded_and_far_from_trees_is_not() -> void:
	var data := _gen(FOREST)
	var chunk := _chunk(data)
	var oaks: PackedFloat32Array = data.vegetation[&"tree_oak"]
	var trunk := Vector3(oaks[3], oaks[7], oaks[11])
	assert_bool(chunk.is_shaded(trunk + Vector3(0.5, 0, 0))).is_true()
	# Find a point of the chunk away from every shade-casting tree.
	var found_open := false
	for i in 400:
		var p := Vector3(float(i % 20) * 3.2, 0.0, float(i / 20) * 3.2)
		if chunk.is_shaded(p):
			continue
		found_open = true
		for id: StringName in data.vegetation:
			var radius := _library.shade_for(id)
			if radius <= 0.0:
				continue
			var buffer: PackedFloat32Array = data.vegetation[id]
			for o in range(0, buffer.size(), 12):
				var scale := Vector3(buffer[o], buffer[o + 4], buffer[o + 8]).length()
				var d := Vector2(p.x - buffer[o + 3], p.z - buffer[o + 11]).length()
				assert_float(d).is_greater(radius * scale)
		break
	assert_bool(found_open).is_true()


func test_only_trees_cast_shade() -> void:
	for id: StringName in _library.ids():
		assert_bool(_library.shade_for(id) > 0.0).is_equal(String(id).begins_with("tree_"))


func test_den_logs_grow_and_offer_rest_to_every_species() -> void:
	var dens := 0
	var rest_targets := 0
	for i in 12:
		var data := _gen(FOREST + Vector2i(i % 4, i / 4))
		dens += data.vegetation_count(&"den_log")
		var chunk := _chunk(data)
		var fox_diet: Array[StringName] = [&"berries"]
		chunk.apply(data, load(MATERIAL_PATH), _library, fox_diet)  # dens are not food
		for t in chunk.food_count():
			var target := chunk.interaction_target(t)
			if target.definition.type == InteractionDefinition.Type.REST:
				rest_targets += 1
				assert_bool(target.is_available()).is_true()
				target.consume()
				assert_bool(target.is_available()).is_true()  # a den never runs out
	assert_int(dens).is_greater(0)
	assert_int(rest_targets).is_equal(dens)
