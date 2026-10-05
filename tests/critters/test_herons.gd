## Tests for herons, the critter layer's waders: they stand only in shallow water, step slowly
## about without leaving it, and a running fox makes them fly off, wings beating, to shallow
## water farther away.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const HERON: CritterKind = preload("res://data/critters/heron.tres")
const SEED: int = 12345
## Chunks in the first wetland band with seed 12345 (≈ 2.4–3.2 km east of the spawn).
const WETLAND_CHUNK := Vector2i(44, 0)

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
	player.position = Vector3(100000, 0, 100000)
	add_child(player)
	var system: CritterSystem = auto_free(CritterSystem.new())
	system.kinds = [HERON] as Array[CritterKind]
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


func _assert_wading(system: CritterSystem) -> void:
	var sampler := HeightSampler.new(TERRAIN, SEED)
	for i in system.count():
		var at := system.position_of(i)
		var depth := TERRAIN.sea_level - sampler.height_at(at.x, at.z)
		assert_float(depth).is_between(HERON.wade_depth.x - 0.01, HERON.wade_depth.y + 0.01)
		assert_float(at.y).is_equal_approx(TERRAIN.sea_level - depth, 0.05)  # on the bed (mid-step)


func test_herons_stand_only_in_shallow_water() -> void:
	var system: CritterSystem = _system()[0]
	system.sync(_around(WETLAND_CHUNK, 3))
	assert_int(system.count()).is_greater(3)
	_assert_wading(system)
	var dry: CritterSystem = _system()[0]
	dry.sync(_around(Vector2i.ZERO, 2))  # the spawn meadow has none
	assert_int(dry.count()).is_equal(0)


func test_they_wade_slowly_about_without_leaving_the_shallows() -> void:
	var system: CritterSystem = _system()[0]
	system.sync(_around(WETLAND_CHUNK, 3))
	var start := system.position_of(0)
	var moved := 0.0
	for t in int(60.0 * SETTINGS.sim_hz):
		_step(system)
		moved = maxf(moved, system.position_of(0).distance_to(start))
		assert_bool(system.is_flying(0)).is_false()  # nothing scares them
	assert_float(moved).is_between(0.3, HERON.home_radius * 2.0 + 0.5)
	_assert_wading(system)


func test_a_running_fox_makes_one_fly_off_to_shallow_water_farther_away() -> void:
	var made := _system()
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	system.sync(_around(WETLAND_CHUNK, 3))
	var heron := system.position_of(0)
	player.position = heron + Vector3(10.0, 0.0, 0.0)
	system.tick(0.0)
	var flew := false
	var highest := -INF
	for t in int(1.0 * SETTINGS.sim_hz):  # running at it
		player.position += (heron - player.position).normalized() * 7.5 / SETTINGS.sim_hz
		_step(system)
		flew = flew or system.is_flying(0)
	assert_bool(flew).is_true()
	assert_int(system.splashes).is_greater(0)  # it takes off from the water
	# Wings beat while flying: draw() passes is_flying() to the shader (the headless renderer
	# keeps no MultiMesh data to read back).
	assert_bool(system.is_flying(0)).is_true()
	for t in int(HERON.flee_hop.z * SETTINGS.sim_hz):
		_step(system)
		highest = maxf(highest, system.position_of(0).y)
	assert_float(highest - TERRAIN.sea_level).is_greater(2.0)  # a real flight, not a hop
	for t in int(4.0 * SETTINGS.sim_hz):  # the fox stops; it settles
		_step(system)
	assert_bool(system.is_flying(0)).is_false()
	var landed := system.position_of(0)
	assert_float(Vector2(landed.x - heron.x, landed.z - heron.z).length()).is_greater(8.0)
	_assert_wading(system)
