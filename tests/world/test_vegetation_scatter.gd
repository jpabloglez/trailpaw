## Tests for [VegetationScatterer]: determinism, water and slope rules, surface placement,
## densities and LOD filtering.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const SEED: int = 12345
const MEADOW := Vector2i(3, 3)
const FOREST := Vector2i(17, 2)
const HILLS := Vector2i(43, 0)
const VALLEY := Vector2i(29, -3)

var _settings: TerrainSettings
var _scatterer: VegetationScatterer
var _types: Dictionary = {}


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_scatterer = VegetationScatterer.new(_settings.biomes)
	for file in DirAccess.get_files_at("res://data/vegetation"):
		var type := load("res://data/vegetation".path_join(file)) as VegetationType
		_types[type.id] = type


func _gen(coord: Vector2i, lod: int = 0, world_seed: int = SEED) -> ChunkData:
	return ChunkGenerator.generate_with(
		coord, lod, _settings, HeightSampler.new(_settings, world_seed), _scatterer, world_seed
	)


## Origin of instance [param i] of a MultiMesh buffer.
func _origin(buffer: PackedFloat32Array, i: int) -> Vector3:
	var o := i * VegetationScatterer.FLOATS_PER_INSTANCE
	return Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11])


## Largest max slope any biome allows for [param id].
func _max_slope(id: StringName) -> float:
	var slope := 0.0
	for biome in _settings.biomes.biomes:
		for entry in biome.vegetation:
			if entry.type.id == id:
				slope = maxf(slope, entry.max_slope_degrees)
	return slope


func test_same_seed_places_identically_and_other_seed_differs() -> void:
	assert_str(_gen(FOREST).content_hash()).is_equal(_gen(FOREST).content_hash())
	assert_str(_gen(FOREST, 0, SEED + 1).content_hash()).is_not_equal(_gen(FOREST).content_hash())


func test_worker_thread_scatter_matches_main_thread() -> void:
	var holder: Array[ChunkData] = []
	var job := ChunkJob.new(FOREST, 0, _settings.duplicate(), SEED, _scatterer)
	var task := WorkerThreadPool.add_task(job.run)
	WorkerThreadPool.wait_for_task_completion(task)
	holder.append(job.data)
	assert_str(holder[0].content_hash()).is_equal(_gen(FOREST).content_hash())


## LOD 0 chunks of the river valley band that really have ground below the water.
func _wet_chunks(count: int) -> Array[ChunkData]:
	var found: Array[ChunkData] = []
	var size := _settings.chunk_size
	for i in 40:
		var coord := Vector2i(floori(1700.0 / size) + i, 0)
		var data := _gen(coord)
		if data.has_water():
			found.append(data)
			if found.size() == count:
				break
	return found


func test_nothing_grows_underwater() -> void:
	var wet := _wet_chunks(3)
	assert_int(wet.size()).is_equal(3)  # the test must see real water, not pass vacuously
	var near_water := 0
	for data in wet:
		for id: StringName in data.vegetation:
			var buffer: PackedFloat32Array = data.vegetation[id]
			for i in data.vegetation_count(id):
				var y := _origin(buffer, i).y
				assert_float(y).is_greater_equal(_settings.sea_level)
				near_water += int(y < _settings.sea_level + 1.5)
	assert_int(near_water).is_greater(0)  # shore plants exist right above the waterline


func test_nothing_grows_on_slopes_steeper_than_its_limit() -> void:
	for coord: Vector2i in [HILLS, HILLS + Vector2i(1, 1), FOREST]:
		var data := _gen(coord)
		for id: StringName in data.vegetation:
			if not _scatterer.type_ids().has(id):
				continue  # drops (berries, apples) follow their parent plant, see test_food
			var limit := _max_slope(id) + 0.01
			var buffer: PackedFloat32Array = data.vegetation[id]
			for i in data.vegetation_count(id):
				var p := _origin(buffer, i)
				var normal: Vector3 = VegetationScatterer.surface_at(data, p.x, p.z)[1]
				var slope := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
				(
					assert_float(slope)
					. override_failure_message("%s at %.0f°" % [id, slope])
					. is_less_equal(limit)
				)


func test_instances_sit_on_the_rendered_surface() -> void:
	# Independent check: intersect a vertical ray with the two triangles of the grid cell.
	var data := _gen(HILLS)
	var res := data.resolution
	for id: StringName in data.vegetation:
		var buffer: PackedFloat32Array = data.vegetation[id]
		for i in mini(data.vegetation_count(id), 40):
			var p := _origin(buffer, i)
			var ci := clampi(floori(p.x / data.step), 0, res - 2)
			var cj := clampi(floori(p.z / data.step), 0, res - 2)
			var quad := [
				data.vertices[cj * res + ci],
				data.vertices[cj * res + ci + 1],
				data.vertices[(cj + 1) * res + ci + 1],
				data.vertices[(cj + 1) * res + ci],
			]
			var from := Vector3(p.x, 1000.0, p.z)
			var hit: Variant = null
			for tri: Array in [[0, 1, 2], [0, 2, 3], [1, 2, 3], [1, 3, 0]]:
				var h: Variant = Geometry3D.ray_intersects_triangle(
					from, Vector3.DOWN, quad[tri[0]], quad[tri[1]], quad[tri[2]]
				)
				if (
					h != null
					and (
						hit == null or absf((h as Vector3).y - p.y) < absf((hit as Vector3).y - p.y)
					)
				):
					hit = h
			assert_float(absf((hit as Vector3).y - p.y)).is_less(0.01)


func test_forest_density_matches_the_data() -> void:
	var data := _gen(FOREST)
	var trees := 0
	var expected := 0.0
	for entry in _settings.biomes.biomes[1].vegetation:
		if String(entry.type.id).begins_with("tree_"):
			trees += data.vegetation_count(entry.type.id)
			expected += entry.density * 40.96  # per 100 m² × chunk area / 100
	assert_float(float(trees)).is_between(expected * 0.35, expected * 1.3)


func test_biomes_grow_their_own_vegetation() -> void:
	var meadow := _gen(MEADOW)
	var forest := _gen(FOREST)
	assert_int(meadow.vegetation_count(&"flower_yellowA")).is_greater(10)
	assert_int(forest.vegetation_count(&"flower_yellowA")).is_equal(0)
	assert_int(forest.vegetation_count(&"tree_detailed")).is_greater(3)
	assert_int(meadow.vegetation_count(&"tree_detailed")).is_equal(0)


func test_near_only_types_are_skipped_in_coarse_chunks() -> void:
	var coarse := _gen(MEADOW, 1)
	for id: StringName in coarse.vegetation:
		(
			assert_bool((_types[id] as VegetationType).near_only)
			. override_failure_message(String(id))
			. is_false()
		)
	assert_int(coarse.vegetation_count(&"grass")).is_equal(0)


func test_tree_positions_do_not_depend_on_lod() -> void:
	var fine := _gen(FOREST, 0)
	var coarse := _gen(FOREST, 1)
	var a: PackedFloat32Array = fine.vegetation[&"tree_detailed"]
	var b: PackedFloat32Array = coarse.vegetation.get(&"tree_detailed", PackedFloat32Array())
	# Same candidates: XZ identical wherever both kept the instance (heights differ by mesh).
	var xz_fine := {}
	for i in fine.vegetation_count(&"tree_detailed"):
		var p := _origin(a, i)
		xz_fine[Vector2(p.x, p.z)] = true
	var shared := 0
	for i in b.size() / VegetationScatterer.FLOATS_PER_INSTANCE:
		var p := _origin(b, i)
		shared += int(xz_fine.has(Vector2(p.x, p.z)))
	assert_int(shared).is_greater(0)
	assert_float(float(shared) / fine.vegetation_count(&"tree_detailed")).is_greater(0.7)


func test_density_scale_reduces_instances() -> void:
	var full := _gen(MEADOW)
	var half := ChunkGenerator.generate_with(
		MEADOW, 0, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED, 0.5
	)
	var ratio := float(half.vegetation_count(&"grass")) / full.vegetation_count(&"grass")
	assert_float(ratio).is_between(0.35, 0.65)
