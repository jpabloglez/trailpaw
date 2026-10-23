## Tests for the swans (Phase 19): pairs on deep water of the lakes that stay together, and that
## glide away over the water, never flying, when the fox comes, even walking; together again
## afterwards.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const SWAN: CritterKind = preload("res://data/critters/swan.tres")
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")
const SEED: int = 12345
const Places := preload("res://tests/world/places.gd")

var _saved: Array = []
var _lake: Vector2


func before() -> void:
	_lake = Places.point_in(TERRAIN, HeightSampler.new(TERRAIN, SEED), &"lakes", 0.5)


func before_test() -> void:
	_saved = [GameState.world_seed, GameState.water_level, GameState.game_minutes]
	GameState.world_seed = SEED
	GameState.water_level = TERRAIN.sea_level
	GameState.game_minutes = 12.0 * 60.0


func after_test() -> void:
	GameState.world_seed = _saved[0]
	GameState.water_level = _saved[1]
	GameState.game_minutes = _saved[2]


func _system(around: Vector2 = _lake, reach: int = 6) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	player.position = Vector3(100000, 0, 100000)
	add_child(player)
	var system: CritterSystem = auto_free(CritterSystem.new())
	system.kinds = [SWAN] as Array[CritterKind]
	system.settings = SETTINGS
	system.terrain = TERRAIN
	system.player = player
	add_child(system)
	system.set_physics_process(false)
	system.set_process(false)
	var chunks: Array[Vector2i] = []
	var centre := Vector2i((around / TERRAIN.chunk_size).floor())
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			chunks.append(centre + Vector2i(x, z))
	system.sync(chunks)
	return [system, player]


func _step(system: CritterSystem, seconds: float) -> void:
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(seconds * SETTINGS.sim_hz):
		system.tick(step)
		system.advance_hops(step)


# Distance from swan [param i] to the nearest other swan (its partner).
func _gap(system: CritterSystem, i: int) -> float:
	var best := INF
	for j in system.count():
		if j != i:
			best = minf(best, system.position_of(j).distance_to(system.position_of(i)))
	return best


func test_they_live_in_pairs_on_deep_water_of_the_lakes() -> void:
	var system: CritterSystem = _system()[0]
	assert_int(system.count()).is_greater_equal(4)
	assert_int(system.count() % 2).is_equal(0)  # pairs
	var sampler := HeightSampler.new(TERRAIN, SEED)
	for i in system.count():
		var at := GameState.absolute_position(system.position_of(i))
		assert_float(at.y).is_equal_approx(TERRAIN.sea_level, 1e-3)
		assert_float(sampler.height_at(at.x, at.z)).is_less_equal(
			TERRAIN.sea_level - SWAN.min_depth
		)
		assert_float(_gap(system, i)).is_less_equal(SWAN.group_spread * 2.0 + 0.01)
	var meadow: CritterSystem = _system(Vector2(250.0, -720.0), 3)[0]
	assert_int(meadow.count()).is_equal(0)


func test_the_two_of_a_pair_glide_together() -> void:
	var system: CritterSystem = _system()[0]
	var start := system.position_of(0)
	var travelled := 0.0
	for second in 300:
		_step(system, 1.0)
		for i in system.count():
			assert_float(_gap(system, i)).is_less(6.0)
		travelled = maxf(travelled, system.position_of(0).distance_to(start))
	assert_float(travelled).is_greater(2.0)  # gliding about, not frozen


func test_they_glide_away_from_the_fox_even_walking_and_pair_up_again() -> void:
	var made := _system()
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	var swan := system.position_of(0)
	player.position = swan + Vector3(18.0, 0.0, 0.0)
	system.tick(0.0)
	var step := 1.0 / SETTINGS.sim_hz
	var fled := false
	for t in int(6.0 * SETTINGS.sim_hz):  # walking towards it (1.5 m/s)
		player.position += Vector3(-1.5 * step, 0.0, 0.0)
		system.tick(step)
		system.advance_hops(step)
		fled = fled or system.state_of(0) == CritterSystem.State.FLEE
		assert_float(system.position_of(0).y).is_equal_approx(GameState.water_level, 1e-3)  # never flies
	assert_bool(fled).is_true()
	var now := system.position_of(0)
	assert_float(Vector2(now.x - player.position.x, now.z - player.position.z).length()).is_greater(
		Vector2(swan.x - player.position.x, swan.z - player.position.z).length()
	)
	player.position = swan + Vector3(400.0, 0.0, 0.0)
	_step(system, SWAN.calm_seconds + 40.0)
	assert_float(_gap(system, 0)).is_less(4.0)  # back beside its mate


func test_the_journal_has_the_swan_and_the_mesh_its_size() -> void:
	var entry := JOURNAL.entry(&"swan")
	assert_object(entry).is_not_null()
	assert_object(entry.animal).is_equal(SWAN)
	assert_array(entry.biome_ids(TERRAIN.biomes)).contains([&"lakes"])
	var size := ProceduralMeshes.critter(&"swan").get_aabb().size
	assert_float(size.z).is_between(0.9, 1.1)  # beak to tail
	assert_float(size.y).is_between(0.6, 0.8)  # the head held high
