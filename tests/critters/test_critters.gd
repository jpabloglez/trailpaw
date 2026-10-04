## Tests for the critter layer ([CritterPlan], [CritterSystem]) with rabbits: deterministic and
## biome-bound placement, on dry ground, coming and going with chunks, fleeing from a running
## fox (not a walking one), the floating origin, the cap and the time budget.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const RABBIT: CritterKind = preload("res://data/critters/rabbit.tres")
const SEED: int = 12345

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


func _coords(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			out.append(Vector2i(x, z))
	return out


func _system(settings: CritterSettings = SETTINGS, kinds: Array[CritterKind] = [RABBIT]) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	player.position = Vector3(10000, 0, 10000)  # far away unless a test moves it
	add_child(player)
	var system: CritterSystem = auto_free(CritterSystem.new())
	system.kinds = kinds
	system.settings = settings
	system.terrain = TERRAIN
	system.player = player
	add_child(system)
	system.set_physics_process(false)  # ticked by hand
	system.set_process(false)
	return [system, player]


# --- plan ---------------------------------------------------------------------------------


func test_the_plan_is_deterministic_and_biome_bound() -> void:
	var a := CritterPlan.roll(Vector2i(3, -2), 64.0, &"meadow", RABBIT, SEED)
	var b := CritterPlan.roll(Vector2i(3, -2), 64.0, &"meadow", RABBIT, SEED)
	assert_that(a).is_equal(b)
	assert_int(CritterPlan.roll(Vector2i(3, -2), 64.0, &"forest", RABBIT, SEED).size()).is_equal(0)
	var hosting := 0
	for i in 400:
		var roll := CritterPlan.roll(Vector2i(i % 20, i / 20), 64.0, &"meadow", RABBIT, SEED)
		if not roll.is_empty():
			hosting += 1
			assert_int(roll.size()).is_between(1, 3)
	assert_float(hosting / 400.0).is_between(RABBIT.chance - 0.1, RABBIT.chance + 0.1)


# --- system -------------------------------------------------------------------------------


func test_rabbits_sit_on_dry_ground() -> void:
	var system: CritterSystem = _system()[0]
	system.sync(_coords(2))
	assert_int(system.count()).is_greater(0)
	var sampler := HeightSampler.new(TERRAIN, SEED)
	for i in system.count():
		var at := system.position_of(i)
		assert_float(at.y).is_equal_approx(sampler.height_at(at.x, at.z), 0.01)
		assert_float(at.y).is_greater(TERRAIN.sea_level)


func test_they_come_and_go_with_their_chunks() -> void:
	var system: CritterSystem = _system()[0]
	system.sync(_coords(2))
	var first := system.count()
	var positions := PackedVector3Array()
	for i in first:
		positions.append(system.position_of(i))
	system.sync([] as Array[Vector2i])
	assert_int(system.count()).is_equal(0)
	system.sync(_coords(2))
	assert_int(system.count()).is_equal(first)  # the same chunks bring the same rabbits
	for i in first:
		assert_bool(positions.has(system.position_of(i))).is_true()


func _nearest_calm(system: CritterSystem) -> int:
	for i in system.count():
		if system.state_of(i) != CritterSystem.State.FLEE:
			return i
	return -1


func _approach(
	system: CritterSystem, player: Node3D, rabbit: int, speed: float, seconds: float
) -> void:
	var target := system.position_of(rabbit)
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(seconds * SETTINGS.sim_hz):
		var to := Vector3(target.x - player.position.x, 0.0, target.z - player.position.z)
		if to.length() > 1.6:  # stop short of bumping into it
			player.position += to.normalized() * speed * step
		system.tick(step)
		system.advance_hops(step)


func test_a_running_fox_scares_them_off() -> void:
	var made := _system()
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	system.sync(_coords(2))
	var rabbit := _nearest_calm(system)
	var at := system.position_of(rabbit)
	player.position = at + Vector3(6.0, 0.0, 0.0)
	system.tick(0.0)  # remember where the fox is
	_approach(system, player, rabbit, 7.5, 0.4)  # running
	assert_int(system.state_of(rabbit)).is_equal(CritterSystem.State.FLEE)
	var before := Vector2(at.x - player.position.x, at.z - player.position.z).length()
	for t in int(1.5 * SETTINGS.sim_hz):
		system.tick(1.0 / SETTINGS.sim_hz)
		system.advance_hops(1.0 / SETTINGS.sim_hz)
	var now := system.position_of(rabbit)
	var after := Vector2(now.x - player.position.x, now.z - player.position.z).length()
	assert_float(after).is_greater(before + 2.0)  # it got away


func test_a_walking_fox_does_not() -> void:
	var made := _system()
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	system.sync(_coords(2))
	var rabbit := _nearest_calm(system)
	player.position = system.position_of(rabbit) + Vector3(5.0, 0.0, 0.0)
	system.tick(0.0)
	_approach(system, player, rabbit, 1.1, 2.0)  # walking up, stopping 1.6 m short
	assert_int(system.state_of(rabbit)).is_not_equal(CritterSystem.State.FLEE)


func test_they_follow_a_floating_origin_shift() -> void:
	var system: CritterSystem = _system()[0]
	system.sync(_coords(1))
	assert_int(system.count()).is_greater(0)
	var before := system.position_of(0)
	EventBus.origin_shifted.emit(Vector3(64.0, 0.0, -128.0))
	assert_vector(system.position_of(0)).is_equal_approx(
		before - Vector3(64.0, 0.0, -128.0), Vector3.ONE * 1e-3
	)


func test_the_cap_holds() -> void:
	var small := SETTINGS.duplicate() as CritterSettings
	small.max_total = 5
	var system: CritterSystem = _system(small)[0]
	system.sync(_coords(4))
	assert_int(system.count()).is_less_equal(5)


func test_a_full_population_fits_the_budget() -> void:
	var busy := RABBIT.duplicate() as CritterKind
	busy.chance = 1.0
	busy.biome_counts = {
		&"meadow": Vector2i(3, 3),
		&"hills": Vector2i(3, 3),
		&"forest": Vector2i(3, 3),
		&"river_valley": Vector2i(3, 3)
	}
	var system: CritterSystem = _system(SETTINGS, [busy] as Array[CritterKind])[0]
	system.sync(_coords(6))
	assert_int(system.count()).is_equal(SETTINGS.max_total)
	var step := 1.0 / SETTINGS.sim_hz
	var times := PackedFloat32Array()
	for i in 60:
		var start := Time.get_ticks_usec()
		system.tick(step)
		system.advance_hops(step)
		system.draw()
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	# ≈ 0.3–0.5 ms on the reference machine; the bound leaves room for slower CI runners.
	assert_float(times[times.size() / 2]).is_less(2.0)
