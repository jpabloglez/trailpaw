## Tests for butterflies (by day over flowers, in their biomes, scattering from a running fox)
## and fireflies (at night in the forest and the valley), both off on the Low preset; and the
## chunk's flower spots they rely on.
extends GdUnitTestSuite

const SETTINGS: SmallLifeSettings = preload("res://data/critters/small_life.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SEED: int = 12345
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


func _butterflies(flowers: PackedVector3Array) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var butterflies: Butterflies = auto_free(Butterflies.new())
	butterflies.settings = SETTINGS
	butterflies.player = player
	butterflies.day_night = _cycle()
	butterflies.flower_source = func() -> PackedVector3Array: return flowers
	add_child(butterflies)
	butterflies.set_process(false)
	return [butterflies, player]


func _run(butterflies: Butterflies, seconds: float) -> void:
	for i in int(seconds * 30.0):
		butterflies.step(1.0 / 30.0)


func test_by_day_they_visit_the_flowers() -> void:
	var flowers := _flowers(60)
	var butterflies: Butterflies = _butterflies(flowers)[0]
	_run(butterflies, 2.0)
	assert_int(butterflies.count()).is_equal(60 / SETTINGS.flowers_per_butterfly)
	for i in butterflies.count():
		assert_bool(flowers.has(butterflies.flower_of(i))).is_true()
		assert_float(butterflies.position_of(i).distance_to(butterflies.flower_of(i))).is_less(1.5)
	var many: Butterflies = _butterflies(_flowers(400))[0]
	_run(many, 1.0)
	assert_int(many.count()).is_equal(SETTINGS.max_butterflies)


func test_none_at_night_in_the_forest_or_on_low() -> void:
	var butterflies: Butterflies = _butterflies(_flowers(60))[0]
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
	var butterflies: Butterflies = made[0]
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
	var chunk: TerrainChunk = auto_free(load("res://scenes/world/terrain_chunk.tscn").instantiate())
	add_child(chunk)
	chunk.apply(data, load("res://data/world/terrain_material.tres"), library)
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
