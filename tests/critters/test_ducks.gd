## Tests for ducks, the critter layer's swimmers: only on water deep enough, at its surface,
## staying on it while they paddle about, and fleeing across it with a splash from a running fox.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const DUCK: CritterKind = preload("res://data/critters/duck.tres")
const SEED: int = 12345
## The lake nearest to the spawn with seed 12345 (≈ 250, −720 absolute).
const LAKE_CHUNK := Vector2i(3, -11)

var _saved_seed: int
var _saved_water: float


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_water = GameState.water_level
	GameState.world_seed = SEED
	GameState.water_level = TERRAIN.sea_level


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.water_level = _saved_water


func _around(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			out.append(centre + Vector2i(x, z))
	return out


func _system() -> Array:
	var player: Node3D = auto_free(Node3D.new())
	player.position = Vector3(10000, 0, 10000)
	add_child(player)
	var system: CritterSystem = auto_free(CritterSystem.new())
	system.kinds = [DUCK] as Array[CritterKind]
	system.settings = SETTINGS
	system.terrain = TERRAIN
	system.player = player
	add_child(system)
	system.set_physics_process(false)
	system.set_process(false)
	return [system, player]


func _assert_on_water(system: CritterSystem) -> void:
	var sampler := HeightSampler.new(TERRAIN, SEED)
	for i in system.count():
		var at := system.position_of(i)
		assert_float(at.y).is_equal_approx(TERRAIN.sea_level, 1e-3)
		assert_float(sampler.height_at(at.x, at.z)).is_less_equal(
			TERRAIN.sea_level - DUCK.min_depth
		)


func test_ducks_only_live_on_deep_water() -> void:
	var system: CritterSystem = _system()[0]
	system.sync(_around(LAKE_CHUNK, 2))
	assert_int(system.count()).is_greater(0)
	_assert_on_water(system)
	var dry: CritterSystem = _system()[0]
	dry.sync(_around(Vector2i.ZERO, 1))  # the spawn meadow has no water
	assert_int(dry.count()).is_equal(0)


func test_they_paddle_about_without_leaving_the_water() -> void:
	var system: CritterSystem = _system()[0]
	system.sync(_around(LAKE_CHUNK, 2))
	var start := system.position_of(0)
	var moved := 0.0
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(60.0 * SETTINGS.sim_hz):
		system.tick(step)
		system.advance_hops(step)
		moved = maxf(moved, system.position_of(0).distance_to(start))
	assert_float(moved).is_greater(0.5)
	_assert_on_water(system)


func test_a_running_fox_sends_them_off_across_the_water() -> void:
	var made := _system()
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	system.sync(_around(LAKE_CHUNK, 2))
	var duck := system.position_of(0)
	player.position = duck + Vector3(6.0, 0.0, 0.0)
	system.tick(0.0)
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(0.4 * SETTINGS.sim_hz):  # running at it
		player.position += (duck - player.position).normalized() * 7.5 * step
		system.tick(step)
		system.advance_hops(step)
	assert_int(system.state_of(0)).is_equal(CritterSystem.State.FLEE)
	assert_int(system.splashes).is_greater(0)
	var before := Vector2(duck.x - player.position.x, duck.z - player.position.z).length()
	for t in int(2.0 * SETTINGS.sim_hz):
		system.tick(step)
		system.advance_hops(step)
	var now := system.position_of(0)
	var after := Vector2(now.x - player.position.x, now.z - player.position.z).length()
	assert_float(after).is_greater(before)
	_assert_on_water(system)
