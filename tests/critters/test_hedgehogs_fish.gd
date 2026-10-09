## Tests for the Phase 15b night and water critters: hedgehogs are out only at night and curl
## into a ball instead of fleeing; fish stay hidden in deep water and now and then leap out with
## a splash, landing back in deep water.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const HEDGEHOG: CritterKind = preload("res://data/critters/hedgehog.tres")
const FISH: CritterKind = preload("res://data/critters/fish.tres")
const SEED: int = 12345
## The lake nearest to the spawn with seed 12345 (≈ 250, −720 absolute; see test_ducks.gd).
const LAKE_CHUNK := Vector2i(3, -11)

var _saved_seed: int
var _saved_water: float
var _saved_minutes: float


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_water = GameState.water_level
	_saved_minutes = GameState.game_minutes
	GameState.world_seed = SEED
	GameState.water_level = TERRAIN.sea_level
	GameState.game_minutes = 23.0 * 60.0  # night


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.water_level = _saved_water
	GameState.game_minutes = _saved_minutes


func _around(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			out.append(centre + Vector2i(x, z))
	return out


func _system(kind: CritterKind) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	player.position = Vector3(100000, 0, 100000)
	add_child(player)
	var system: CritterSystem = auto_free(CritterSystem.new())
	system.kinds = [kind] as Array[CritterKind]
	system.settings = SETTINGS
	system.terrain = TERRAIN
	system.player = player
	add_child(system)
	system.set_physics_process(false)
	system.set_process(false)
	return [system, player]


func _step(system: CritterSystem) -> void:
	var step := 1.0 / SETTINGS.sim_hz
	system.tick(step)
	system.advance_hops(step)


func test_hedgehogs_are_out_only_at_night() -> void:
	assert_bool(HEDGEHOG.is_out(23.0)).is_true()
	assert_bool(HEDGEHOG.is_out(3.0)).is_true()  # past midnight
	assert_bool(HEDGEHOG.is_out(13.0)).is_false()
	var system: CritterSystem = _system(HEDGEHOG)[0]
	system.sync(_around(Vector2i.ZERO, 3))
	assert_int(system.count()).is_greater(0)
	system.tick(0.0)
	for i in system.count():
		assert_bool(system.is_shown(i)).is_true()
	GameState.game_minutes = 13.0 * 60.0
	var before := system.position_of(0)
	for t in int(5.0 * SETTINGS.sim_hz):
		_step(system)
	for i in system.count():
		assert_bool(system.is_shown(i)).is_false()  # asleep somewhere: not seen, not moving
	assert_vector(system.position_of(0)).is_equal(before)


func test_a_scared_hedgehog_curls_up_where_it_is() -> void:
	var made := _system(HEDGEHOG)
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	system.sync(_around(Vector2i.ZERO, 3))
	var hedgehog := system.position_of(0)
	player.position = hedgehog + Vector3(4.0, 0.0, 0.0)
	system.tick(0.0)
	for t in int(0.5 * SETTINGS.sim_hz):  # running at it
		player.position += (hedgehog - player.position).normalized() * 7.5 / SETTINGS.sim_hz
		_step(system)
	assert_int(system.state_of(0)).is_equal(CritterSystem.State.FLEE)
	var curled := system.position_of(0)
	for t in int(2.0 * SETTINGS.sim_hz):
		_step(system)
	assert_float(system.position_of(0).distance_to(curled)).is_less(0.01)  # a ball, not running
	player.position = hedgehog + Vector3(30.0, 0.0, 0.0)  # the fox goes away
	for t in int((HEDGEHOG.calm_seconds + 1.0) * SETTINGS.sim_hz):
		_step(system)
	assert_int(system.state_of(0)).is_not_equal(CritterSystem.State.FLEE)  # uncurled


func test_fish_stay_hidden_and_leap_out_now_and_then() -> void:
	var system: CritterSystem = _system(FISH)[0]
	system.sync(_around(LAKE_CHUNK, 2))
	assert_int(system.count()).is_greater(0)
	var sampler := HeightSampler.new(TERRAIN, SEED)
	var leaps := 0
	var highest := -INF
	for i in system.count():
		assert_bool(system.is_shown(i)).is_false()  # under the water
	for t in int(45.0 * SETTINGS.sim_hz):
		_step(system)
		for i in system.count():
			var shown := system.is_shown(i)
			assert_bool(shown).is_equal(system.state_of(i) == CritterSystem.State.LEAP)
			if shown:
				highest = maxf(highest, system.position_of(i).y)
			else:  # wherever it is, the water there is deep enough
				var at := system.position_of(i)
				assert_float(sampler.height_at(at.x, at.z)).is_less_equal(
					TERRAIN.sea_level - FISH.min_depth + 1e-3
				)
		leaps = system.plops
	assert_int(leaps).is_greater(2)  # a plop leaving and one landing per leap
	assert_float(highest - TERRAIN.sea_level).is_between(0.2, 0.6)
	assert_int(system.splashes).is_equal(system.plops)  # every plop splashes
