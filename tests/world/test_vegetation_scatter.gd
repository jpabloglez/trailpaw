## Tests for [VegetationScatterer]: determinism, water and slope rules, surface placement,
## densities and LOD filtering.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const SEED: int = 12345
const MEADOW := Vector2i(3, 3)
const FOREST := Vector2i(17, 2)
const HILLS := Vector2i(56, 0)  # hills since the wetland band (ADR-006)
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


func test_dry_land_plants_never_grow_underwater() -> void:
	var wet := _wet_chunks(3)
	assert_int(wet.size()).is_equal(3)  # the test must see real water, not pass vacuously
	var near_water := 0
	var aquatic := _aquatic_ids()
	for data in wet:
		for id: StringName in data.vegetation:
			if aquatic.has(id):
				continue  # reeds and water lilies belong in the water (Phase 14)
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
	var drops := VegetationLibrary.new(_settings.biomes).drop_ids()
	for id: StringName in data.vegetation:
		if drops.has(id):
			continue  # derived props (berries, fallen apples) sit on their parent plant, not the ground
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


# Types some biome lets grow under the water (an entry with min_height < 0).
func _aquatic_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for biome in _settings.biomes.biomes:
		for entry in biome.vegetation:
			if entry.min_height < 0.0 and not out.has(entry.type.id):
				out.append(entry.type.id)
	return out


func _wetland_chunks(count: int) -> Array[ChunkData]:
	var resolver := BiomeResolver.new(_settings.biomes, SEED)
	var out: Array[ChunkData] = []
	for cx in range(38, 50):
		for cz in range(-3, 4):
			var centre := (Vector2(cx, cz) + Vector2(0.5, 0.5)) * _settings.chunk_size
			if resolver.dominant_at(centre.x, centre.y).id != &"wetland":
				continue
			var data := _gen(Vector2i(cx, cz))
			if data.has_water():
				out.append(data)
				if out.size() >= count:
					return out
	return out


func test_water_lilies_float_on_the_water_where_it_is_deep_enough() -> void:
	var lilies := 0
	for data in _wetland_chunks(3):
		for id: StringName in [&"water_lily", &"water_lily_flower"]:
			var buffer: PackedFloat32Array = data.vegetation.get(id, PackedFloat32Array())
			for i in buffer.size() / VegetationScatterer.FLOATS_PER_INSTANCE:
				var p := _origin(buffer, i)
				assert_float(p.y).is_equal_approx(_settings.sea_level, 1e-4)  # at the surface
				var ground: float = VegetationScatterer.surface_at(data, p.x, p.z)[0]
				var depth := _settings.sea_level - ground
				assert_float(depth).is_between(0.29, 1.61)  # over the depths the entry allows
				lilies += 1
	assert_int(lilies).is_greater(10)


func test_reeds_stand_on_the_banks_and_in_the_shallows_only() -> void:
	var reeds := 0
	var in_water := 0
	for data in _wetland_chunks(3):
		var buffer: PackedFloat32Array = data.vegetation.get(&"reeds", PackedFloat32Array())
		for i in buffer.size() / VegetationScatterer.FLOATS_PER_INSTANCE:
			var p := _origin(buffer, i)
			var height := p.y - _settings.sea_level
			assert_float(height).is_between(-0.36, 0.51)
			in_water += int(height < 0.0)
			reeds += 1
	assert_int(reeds).is_greater(50)
	assert_int(in_water).is_greater(0)  # some really stand in the water


func test_aquatic_plants_are_deterministic() -> void:
	var chunks := _wetland_chunks(1)
	assert_int(chunks.size()).is_equal(1)
	var again := _gen(chunks[0].coord)
	assert_that(again.vegetation.get(&"water_lily")).is_equal(
		chunks[0].vegetation.get(&"water_lily")
	)
	assert_that(again.vegetation.get(&"reeds")).is_equal(chunks[0].vegetation.get(&"reeds"))
