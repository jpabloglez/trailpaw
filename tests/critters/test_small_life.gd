## Tests for butterflies (by day over flowers, in their biomes, scattering from a running fox),
## dragonflies (by day, darting over the water plants of the wetland and the valley) and
## fireflies (at night in the forest and the valley), all off on the Low preset; and the chunk's
## flower and water-plant spots they rely on.
extends GdUnitTestSuite

const SETTINGS: SmallLifeSettings = preload("res://data/critters/small_life.tres")
const BUTTERFLIES: FlitterKind = preload("res://data/critters/butterflies.tres")
const DRAGONFLIES: FlitterKind = preload("res://data/critters/dragonflies.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SEED: int = 12345
const CHUNK_SCENE: PackedScene = preload("res://scenes/world/terrain_chunk.tscn")
const TERRAIN_MATERIAL: Material = preload("res://data/world/terrain_material.tres")
const LOW: QualityPreset = preload("res://data/quality/low.tres")

var _saved_biome: StringName
var _saved_minutes: float
var _saved_quality: QualityPreset


func before_test() -> void:
	_saved_biome = GameState.current_biome
	_saved_minutes = GameState.game_minutes
	_saved_quality = Settings.quality
	GameState.current_biome = &"meadow"
	GameState.game_minutes = 12.0 * 60.0


func after_test() -> void:
	GameState.current_biome = _saved_biome
	GameState.game_minutes = _saved_minutes
	Settings.set_quality(_saved_quality)


func _cycle() -> DayNightCycle:
	var cycle: DayNightCycle = auto_free(DayNightCycle.new())
	cycle.settings = load("res://data/world/day_night.tres")
	return cycle


func _flowers(count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		out.append(Vector3(cos(i * 1.7) * (2.0 + i * 0.2), 0.0, sin(i * 1.7) * (2.0 + i * 0.2)))
	return out


func _butterflies(flowers: PackedVector3Array, kind: FlitterKind = BUTTERFLIES) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var butterflies: Flitters = auto_free(Flitters.new())
	butterflies.kind = kind
	butterflies.player = player
	butterflies.day_night = _cycle()
	butterflies.spot_source = func() -> PackedVector3Array: return flowers
	add_child(butterflies)
	butterflies.set_process(false)
	return [butterflies, player]


func _run(butterflies: Flitters, seconds: float) -> void:
	for i in int(seconds * 30.0):
		butterflies.step(1.0 / 30.0)


func test_by_day_they_visit_the_flowers() -> void:
	var flowers := _flowers(60)
	var butterflies: Flitters = _butterflies(flowers)[0]
	_run(butterflies, 2.0)
	assert_int(butterflies.count()).is_equal(60 / BUTTERFLIES.spots_per_flier)
	for i in butterflies.count():
		assert_bool(flowers.has(butterflies.spot_of(i))).is_true()
		assert_float(butterflies.position_of(i).distance_to(butterflies.spot_of(i))).is_less(1.5)
	var many: Flitters = _butterflies(_flowers(400))[0]
	_run(many, 1.0)
	assert_int(many.count()).is_equal(BUTTERFLIES.max_count)


func test_none_at_night_in_the_forest_or_on_low() -> void:
	var butterflies: Flitters = _butterflies(_flowers(60))[0]
	GameState.game_minutes = 1.0 * 60.0
	_run(butterflies, 1.0)
	assert_int(butterflies.count()).is_equal(0)
	GameState.game_minutes = 12.0 * 60.0
	GameState.current_biome = &"forest"
	_run(butterflies, 1.0)
	assert_int(butterflies.count()).is_equal(0)
	GameState.current_biome = &"meadow"
	Settings.set_quality(LOW)
	_run(butterflies, 1.0)
	assert_int(butterflies.count()).is_equal(0)


func test_running_through_scatters_them() -> void:
	var made := _butterflies(_flowers(60))
	var butterflies: Flitters = made[0]
	var player: Node3D = made[1]
	_run(butterflies, 2.0)
	var target := butterflies.position_of(0)
	player.position = target + Vector3(4.0, -target.y, 0.0)
	butterflies.step(1.0 / 30.0)
	for i in 30:
		player.position += Vector3(-0.25, 0, 0)  # 7.5 m/s straight through
		butterflies.step(1.0 / 30.0)
		if butterflies.is_scattering(0):
			break
	assert_bool(butterflies.is_scattering(0)).is_true()


func test_flower_spots_are_the_chunks_flowers() -> void:
	var library := VegetationLibrary.new(TERRAIN.biomes)
	var data := ChunkGenerator.generate_with(
		Vector2i(0, 0),
		0,
		TERRAIN,
		HeightSampler.new(TERRAIN, SEED),
		VegetationScatterer.new(TERRAIN.biomes),
		SEED
	)
	var chunk: TerrainChunk = auto_free(CHUNK_SCENE.instantiate())
	add_child(chunk)
	chunk.apply(data, TERRAIN_MATERIAL, library)
	var spots := PackedVector3Array()
	chunk.spots(&"flower", spots)
	var expected := 0
	for id: StringName in data.vegetation:
		if String(id).begins_with("flower"):
			expected += data.vegetation_count(id)
	assert_int(expected).is_greater(0)
	assert_int(spots.size()).is_equal(expected)


func _fireflies() -> Fireflies:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var fireflies: Fireflies = auto_free(Fireflies.new())
	fireflies.settings = SETTINGS
	fireflies.player = player
	fireflies.day_night = _cycle()
	add_child(fireflies)
	fireflies.set_process(false)
	return fireflies


func test_fireflies_glow_at_night_in_the_forest() -> void:
	var fireflies := _fireflies()
	GameState.current_biome = &"forest"
	GameState.game_minutes = 1.0 * 60.0
	fireflies._process(0.016)
	assert_bool(fireflies.emitting).is_true()
	assert_float(fireflies.amount_ratio).is_greater(0.5)
	GameState.game_minutes = 12.0 * 60.0
	fireflies._process(0.016)
	assert_bool(fireflies.emitting).is_false()
	GameState.game_minutes = 1.0 * 60.0
	GameState.current_biome = &"hills"
	fireflies._process(0.016)
	assert_bool(fireflies.emitting).is_false()
	GameState.current_biome = &"forest"
	Settings.set_quality(LOW)
	fireflies._process(0.016)
	assert_bool(fireflies.emitting).is_false()


func test_dragonflies_dart_over_the_water_plants_by_day() -> void:
	GameState.current_biome = &"wetland"
	var plants := _flowers(100)
	var dragonflies: Flitters = _butterflies(plants, DRAGONFLIES)[0]
	_run(dragonflies, 1.0)
	assert_int(dragonflies.count()).is_equal(100 / DRAGONFLIES.spots_per_flier)
	var hovering := 0
	var dashes := 0
	var last := dragonflies.position_of(0)
	var still := 0
	var near := 0  # around their spot (not on the way to another)
	var samples := 0
	for t in 300:  # 10 s
		dragonflies.step(1.0 / 30.0)
		var now := dragonflies.position_of(0)
		var speed := now.distance_to(last) * 30.0
		hovering += int(speed < 0.05)
		dashes += int(speed > 3.0 and still > 5)  # a dash right after hovering
		still = still + 1 if speed < 0.05 else 0
		last = now
		for i in dragonflies.count():
			var spot := dragonflies.spot_of(i)
			assert_bool(plants.has(spot)).is_true()
			var offset := dragonflies.position_of(i) - spot
			near += int(Vector2(offset.x, offset.z).length() < DRAGONFLIES.loop_radius + 0.1)
			samples += 1
	assert_int(hovering).is_greater(60)  # they hang still in the air...
	assert_int(dashes).is_greater(2)  # ... and dart off
	assert_float(float(near) / samples).is_greater(0.6)  # mostly around their spot
	GameState.current_biome = &"meadow"  # not their biome
	_run(dragonflies, 1.0)
	assert_int(dragonflies.count()).is_equal(0)
	GameState.current_biome = &"wetland"
	GameState.game_minutes = 1.0 * 60.0  # not at night
	_run(dragonflies, 1.0)
	assert_int(dragonflies.count()).is_equal(0)


func test_water_plant_spots_are_the_chunks_reeds_and_lilies() -> void:
	var library := VegetationLibrary.new(TERRAIN.biomes)
	var data := ChunkGenerator.generate_with(
		Vector2i(44, 0),
		0,
		TERRAIN,
		HeightSampler.new(TERRAIN, SEED),
		VegetationScatterer.new(TERRAIN.biomes),
		SEED
	)
	var chunk: TerrainChunk = auto_free(CHUNK_SCENE.instantiate())
	add_child(chunk)
	chunk.apply(data, TERRAIN_MATERIAL, library)
	var spots := PackedVector3Array()
	chunk.spots(&"water_plant", spots)
	var expected := 0
	for id in TerrainChunk.WATER_PLANTS:
		expected += data.vegetation_count(id) if data.vegetation.has(id) else 0
	assert_int(expected).is_greater(20)  # a wetland chunk
	assert_int(spots.size()).is_equal(expected)
	var flowers := PackedVector3Array()
	chunk.spots(&"flower", flowers)
	for spot in flowers:  # water lily flowers are water plants, not meadow flowers
		assert_bool(spots.has(spot)).is_false()
