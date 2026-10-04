## Tests for the wetland (ADR-006): its place after the river valley, lots of shallow water,
## and the systems that list biomes knowing about it (sound, animals, plants).
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const WETLAND: BiomeDefinition = preload("res://data/biomes/wetland.tres")
const AMBIENCE: AmbienceSettings = preload("res://data/audio/ambience.tres")
const SEED: int = 12345


func test_it_comes_right_after_the_river_valley() -> void:
	var ids: Array[StringName] = []
	for biome in TERRAIN.biomes.biomes:
		ids.append(biome.id)
	assert_int(ids.find(&"wetland")).is_equal(ids.find(&"river_valley") + 1)


func test_it_is_mostly_shallow_water() -> void:
	var sampler := HeightSampler.new(TERRAIN, SEED)
	var resolver := sampler.resolver()
	var land := 0
	var water := 0
	var shallow := 0
	for i in 6000:
		var angle := float(i) * 2.399963  # golden-angle spiral over the whole band
		var distance := 2450.0 + fmod(float(i) * 37.0, 700.0)
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		if resolver.dominant_at(x, z).id != &"wetland":
			continue
		var depth := TERRAIN.sea_level - sampler.height_at(x, z)
		if depth <= 0.0:
			land += 1
		else:
			water += 1
			shallow += int(depth < 1.2)
	var total := land + water
	assert_int(total).is_greater(1000)
	# Measured 43 % with seed 12345 (the river valley has ≈ 21 %); 93 % of it wadeable.
	assert_float(float(water) / total).is_between(0.3, 0.6)
	assert_float(float(shallow) / water).is_greater(0.8)


func test_it_has_sound_animals_and_plants() -> void:
	var heard := 0
	for layer in AMBIENCE.layers:
		if layer.volume_for(&"wetland", 1.0, 0.0) > 0.0:
			heard += 1
	assert_int(heard).is_greater_equal(2)
	assert_bool(WETLAND.fauna.is_empty()).is_false()
	assert_bool(WETLAND.vegetation.is_empty()).is_false()
	assert_float(WETLAND.warmth).is_less(0.0)  # cool and damp
	var birds: BirdSettings = load("res://data/critters/birds.tres")
	assert_float(birds.biome_chance.get(&"wetland", 0.0)).is_greater(0.0)
	var duck: CritterKind = load("res://data/critters/duck.tres")
	assert_bool(duck.biome_counts.has(&"wetland")).is_true()
