## Tests for food sources: berry clusters on bushes and apples under oaks (derived drops),
## chunk food targets, depletion, regrowth and diets.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const SEED: int = 12345
const FOREST := Vector2i(17, 2)
const MEADOW := Vector2i(3, 3)
const VALLEY := Vector2i(29, -3)
const FOX_DIET: Array[StringName] = [&"berries", &"fruit", &"mushroom", &"eggs", &"vegetables"]

var _settings: TerrainSettings
var _scatterer: VegetationScatterer
var _library: VegetationLibrary
var _saved_minutes: float


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_scatterer = VegetationScatterer.new(_settings.biomes)
	_library = VegetationLibrary.new(_settings.biomes)


func before_test() -> void:
	_saved_minutes = GameState.game_minutes


func after_test() -> void:
	GameState.game_minutes = _saved_minutes


func _gen(coord: Vector2i, lod: int = 0) -> ChunkData:
	return ChunkGenerator.generate_with(
		coord, lod, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED
	)


func _origins(data: ChunkData, id: StringName) -> PackedVector3Array:
	var out := PackedVector3Array()
	var buffer: PackedFloat32Array = data.vegetation.get(id, PackedFloat32Array())
	for i in data.vegetation_count(id):
		var o := i * VegetationScatterer.FLOATS_PER_INSTANCE
		out.append(Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11]))
	return out


func _nearest_horizontal(points: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	for q in points:
		best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best


func _chunk(coord: Vector2i, kinds: Array[StringName] = FOX_DIET) -> TerrainChunk:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	chunk.apply(_gen(coord), load(MATERIAL_PATH), _library, kinds)
	return chunk


# --- placement ----------------------------------------------------------------------------


func test_forest_has_berries_apples_and_mushrooms() -> void:
	var data := _gen(FOREST)
	assert_int(data.vegetation_count(&"berries")).is_greater(0)
	assert_int(data.vegetation_count(&"apple")).is_greater(0)
	assert_int(data.vegetation_count(&"mushroom_tan")).is_greater(0)


func test_drops_are_deterministic() -> void:
	for id: StringName in [&"berries", &"apple"]:
		assert_array(Array(_gen(FOREST).vegetation[id])).is_equal(
			Array(_gen(FOREST).vegetation[id])
		)


func test_drops_only_in_full_detail_chunks_and_parents_keep_their_place() -> void:
	var fine := _gen(FOREST, 0)
	var coarse := _gen(FOREST, 1)
	assert_bool(coarse.vegetation.has(&"berries")).is_false()
	assert_bool(coarse.vegetation.has(&"apple")).is_false()
	# Bushes and oaks (the parents) do not depend on the LOD, so drops never move.
	for id: StringName in [&"berry_bush", &"tree_oak"]:
		var a := _origins(fine, id)
		var b := _origins(coarse, id)
		assert_int(a.size()).is_equal(b.size())
		for i in a.size():
			assert_float(Vector2(a[i].x - b[i].x, a[i].z - b[i].z).length()).is_less(1e-3)


func test_apples_lie_on_the_ground_under_oaks() -> void:
	var oak := load("res://data/vegetation/tree_oak.tres") as VegetationType
	var reach := oak.drop.radius_max * oak.scale_max + 0.01
	for coord: Vector2i in [FOREST, MEADOW]:
		var data := _gen(coord)
		var oaks := _origins(data, &"tree_oak")
		for apple in _origins(data, &"apple"):
			assert_float(_nearest_horizontal(oaks, apple)).is_less_equal(reach)
			var ground: float = VegetationScatterer.surface_at(data, apple.x, apple.z)[0]
			assert_float(apple.y).is_equal_approx(ground, 1e-3)


func test_berries_sit_on_their_bushes() -> void:
	var bush := load("res://data/vegetation/berry_bush.tres") as VegetationType
	var reach := bush.drop.radius_max * bush.scale_max * 1.2 + 0.01  # tilt allowance
	var data := _gen(FOREST)
	var bushes := _origins(data, &"berry_bush")
	for berry in _origins(data, &"berries"):
		assert_float(_nearest_horizontal(bushes, berry)).is_less_equal(reach)


func test_no_food_underwater() -> void:
	var wet_with_food := 0
	# Search the valley band for chunks that have both water and food nearby.
	for i in 40:
		var coord := VALLEY + Vector2i(i % 8 - 4, i / 8 - 2)
		var data := _gen(coord)
		if not data.has_water():
			continue
		var food := 0
		for id: StringName in [&"berries", &"apple", &"mushroom_tan", &"berry_bush"]:
			for p in _origins(data, id):
				assert_float(p.y).is_greater_equal(_settings.sea_level)
				food += 1
		wet_with_food += int(data.has_water() and food > 0)
	assert_int(wet_with_food).is_greater(0)  # the rule was really exercised


func test_drops_stay_dry_even_on_plants_that_grow_underwater() -> void:
	# A table where berry bushes may grow underwater: their berries must still stay dry.
	var settings := _settings.duplicate() as TerrainSettings
	settings.biomes = _settings.biomes.duplicate() as BiomeTable
	var biomes: Array[BiomeDefinition] = []
	for biome in _settings.biomes.biomes:
		var copy := biome.duplicate() as BiomeDefinition
		var entries: Array[VegetationEntry] = []
		for entry in biome.vegetation:
			var e := entry.duplicate() as VegetationEntry
			if e.type.id == &"berry_bush":
				e.min_height = -100.0
				e.density = 6.0
			entries.append(e)
		copy.vegetation = entries
		biomes.append(copy)
	settings.biomes.biomes = biomes
	var scatterer := VegetationScatterer.new(settings.biomes)
	var submerged := 0
	var berries := 0
	for i in 40:
		var coord := VALLEY + Vector2i(i % 8 - 4, i / 8 - 2)
		var data := ChunkGenerator.generate_with(
			coord, 0, settings, HeightSampler.new(settings, SEED), scatterer, SEED
		)
		for bush in _origins(data, &"berry_bush"):
			submerged += int(bush.y < settings.sea_level)
		for berry in _origins(data, &"berries"):
			berries += 1
			assert_float(berry.y).is_greater_equal(settings.sea_level)
	assert_int(submerged).is_greater(0)
	assert_int(berries).is_greater(0)


# --- chunk targets ------------------------------------------------------------------------


func test_one_target_per_edible_instance_in_the_diet() -> void:
	var data := _gen(MEADOW)
	var fox_food := 0
	for id: StringName in [&"berries", &"apple", &"mushroom_tan"]:
		fox_food += data.vegetation_count(id)
	var grass := data.vegetation_count(&"grass_large")
	assert_int(grass).is_greater(0)
	assert_int(_chunk(MEADOW).food_count()).is_equal(fox_food)  # no grass for the fox
	var no_filter: Array[StringName] = []
	assert_int(_chunk(MEADOW, no_filter).food_count()).is_equal(fox_food + grass)


func test_coarse_chunks_have_no_food_targets() -> void:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	chunk.apply(_gen(FOREST, 1), load(MATERIAL_PATH), _library, FOX_DIET)
	assert_int(chunk.food_count()).is_equal(0)


func test_eating_depletes_until_regrowth() -> void:
	var chunk := _chunk(FOREST)
	var target := chunk.interaction_target(0)
	assert_object(target).is_not_null()
	assert_bool(target.is_available()).is_true()
	var definition := target.definition
	GameState.game_minutes = 1000.0
	target.consume()
	assert_bool(target.is_available()).is_false()
	GameState.game_minutes = 1000.0 + definition.regrowth_minutes - 1.0
	chunk.regrow()
	assert_bool(target.is_available()).is_false()
	GameState.game_minutes = 1000.0 + definition.regrowth_minutes
	chunk.regrow()
	assert_bool(target.is_available()).is_true()


func test_target_carries_the_food_definition_and_position() -> void:
	var chunk := _chunk(FOREST)
	var kinds := {}
	for i in chunk.food_count():
		var target := chunk.interaction_target(i)
		if target.definition.type != InteractionDefinition.Type.EAT:
			continue  # dens (REST) are chunk targets too
		kinds[target.definition.food_kind] = true
		assert_bool(FOX_DIET.has(target.definition.food_kind)).is_true()
	assert_int(kinds.size()).is_equal(3)


func test_reapplying_the_same_chunk_keeps_it_eaten_but_a_new_chunk_is_fresh() -> void:
	var chunk := _chunk(FOREST)
	var target := chunk.interaction_target(0)
	target.consume()
	chunk.apply(_gen(FOREST), load(MATERIAL_PATH), _library, FOX_DIET)  # e.g. LOD refresh
	assert_bool(chunk.interaction_target(0).is_available()).is_false()
	chunk.apply(_gen(MEADOW), load(MATERIAL_PATH), _library, FOX_DIET)
	assert_bool(chunk.interaction_target(0).is_available()).is_true()


# --- diet ---------------------------------------------------------------------------------


func test_fox_eats_berries_fruit_mushrooms_and_hamlet_food_not_grass() -> void:
	var fox := load("res://data/species/fox.tres") as AnimalSpecies
	assert_array(fox.diet).contains_exactly_in_any_order(FOX_DIET)
	for id: StringName in [&"berries", &"apple", &"mushroom", &"grass"]:
		var food := load("res://data/interactions/%s.tres" % id) as InteractionDefinition
		assert_array(Array(food.get_validation_errors())).is_empty()
		assert_bool(fox.diet.has(food.food_kind)).is_equal(id != &"grass")


# --- end to end ---------------------------------------------------------------------------


func test_the_fox_eats_berries_from_a_bush() -> void:
	var chunk := _chunk(FOREST)
	var berry := -1
	for i in chunk.food_count():
		if chunk.interaction_target(i).definition.id == &"berries":
			berry = i
			break
	assert_int(berry).is_greater_equal(0)
	var target_position := chunk.interaction_target(berry).position
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.get_node("%PlayerInput").set_physics_process(false)
	add_child(animal)
	animal.global_position = target_position + Vector3(0.0, 0.5, 0.6)  # just south, facing -Z
	for i in 60:
		await get_tree().physics_frame
	var needs := animal.get_node("%NeedsComponent") as NeedsComponent
	needs.set_value(&"hunger", 40.0)
	var interactor := animal.get_node("%Interactor") as Interactor
	interactor.probe()
	assert_object(interactor.current_target()).is_not_null()
	assert_str(interactor.current_target().definition.prompt).is_equal("Eat berries")
	interactor.request_interaction()
	await get_tree().create_timer(2.4).timeout
	assert_float(needs.value(&"hunger")).is_between(59.0, 60.0)
	(
		assert_bool(chunk.is_depleted(&"berries", chunk.interaction_target(berry).key & 0xFFFF))
		. is_true()
	)
