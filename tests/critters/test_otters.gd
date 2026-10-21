## Tests for the otters (Phase 19): they live in the lakes, glide in water deep enough, dive and
## come up elsewhere, float on their backs and climb out on the banks to roll; curious, they
## watch a still fox and back off when it comes close, and startled they dive and come up out of
## its reach; a family lives at each otter den of the island treasures.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const OTTER: CritterKind = preload("res://data/critters/otter.tres")
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")
const SEED: int = 12345
const Places := preload("res://tests/world/places.gd")

var _saved: Array = []
var _lake: Vector2  # the middle of the lake band (found, not fixed)


func before() -> void:
	_lake = Places.point_in(TERRAIN, HeightSampler.new(TERRAIN, SEED), &"lakes", 0.5)


func before_test() -> void:
	_saved = [GameState.world_seed, GameState.water_level, GameState.game_minutes]
	GameState.world_seed = SEED
	GameState.water_level = TERRAIN.sea_level
	GameState.game_minutes = 12.0 * 60.0
	IslandPlan.clear_cache()


func after_test() -> void:
	GameState.world_seed = _saved[0]
	GameState.water_level = _saved[1]
	GameState.game_minutes = _saved[2]
	IslandPlan.clear_cache()


func _system(around: Vector2, kind: CritterKind = OTTER, reach: int = 6) -> Array:
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


func _ground(at: Vector3) -> float:
	var abs := GameState.absolute_position(at)
	return HeightSampler.new(TERRAIN, SEED).height_at(abs.x, abs.z)


# The first otter at rest in the water, or −1.
func _swimming_otter(system: CritterSystem) -> int:
	for i in system.count():
		if system.is_swimming(i) and system.is_shown(i):
			return i
	return -1


func test_otters_live_in_deep_water_of_the_lakes() -> void:
	var system: CritterSystem = _system(_lake)[0]
	assert_int(system.count()).is_greater(3)
	var resolver := HeightSampler.new(TERRAIN, SEED).resolver()
	for i in system.count():
		var at := system.position_of(i)
		assert_bool(system.is_swimming(i)).is_true()
		assert_float(_ground(at)).is_less_equal(TERRAIN.sea_level - OTTER.min_depth)
		var abs := GameState.absolute_position(at)
		(
			assert_bool(
				[&"lakes", &"mountains", &"hills"].has(resolver.dominant_at(abs.x, abs.z).id)
			)
			. is_true()
		)
	var meadow: CritterSystem = _system(Vector2(250.0, -720.0), OTTER, 3)[0]  # the meadow lake
	assert_int(meadow.count()).is_equal(0)


func test_left_alone_they_swim_dive_float_on_their_backs_and_roll_on_the_banks() -> void:
	var system: CritterSystem = _system(_lake)[0]
	var dived := false
	var on_back := false
	var rolling := false
	var moved := false
	var start := system.position_of(0)
	var sampler := HeightSampler.new(TERRAIN, SEED)
	for second in 240:
		_step(system, 1.0)
		for i in system.count():
			dived = dived or system.state_of(i) == CritterSystem.State.UNDER
			on_back = on_back or system.pose_of(i) == CritterSystem.Pose.ON_BACK
			var at := system.position_of(i)
			var abs := GameState.absolute_position(at)
			var ground := sampler.height_at(abs.x, abs.z)
			if system.state_of(i) != CritterSystem.State.IDLE:
				continue  # only places where it rests
			if system.is_swimming(i):
				assert_float(ground).is_less_equal(TERRAIN.sea_level - OTTER.min_depth + 0.01)
			else:
				rolling = rolling or system.pose_of(i) == CritterSystem.Pose.ROLLING
				assert_float(ground - TERRAIN.sea_level).is_between(0.0, OTTER.bank_height)
		moved = moved or system.position_of(0).distance_to(start) > 1.0
	assert_bool(dived).is_true()
	assert_bool(on_back).is_true()
	assert_bool(rolling).is_true()
	assert_bool(moved).is_true()
	assert_int(system.plops).is_greater(0)


func test_the_poses_show_belly_up_and_rolling() -> void:
	var system: CritterSystem = _system(_lake)[0]
	var seen_back := false
	var seen_roll := false
	for second in 240:
		_step(system, 1.0)
		for i in system.count():
			match system.pose_of(i):
				CritterSystem.Pose.ON_BACK:
					assert_float(system.basis_of(i).y.y).is_less(0.0)  # upside down
					seen_back = true
				CritterSystem.Pose.ROLLING:
					seen_roll = true
				CritterSystem.Pose.NONE:
					assert_float(system.basis_of(i).y.y).is_greater(0.0)
		if seen_back and seen_roll:
			break
	assert_bool(seen_back and seen_roll).is_true()


func test_a_still_fox_is_watched_from_a_safe_distance() -> void:
	var made := _system(_lake)
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	var i := _swimming_otter(system)
	var otter := system.position_of(i)
	player.position = otter + Vector3(8.0, 0.0, 0.0)
	system.tick(0.0)
	_step(system, 6.0)
	assert_bool(system.is_shown(i)).is_true()  # it did not dive away
	var now := system.position_of(i)
	var facing := -system.basis_of(i).z.normalized()
	var to_fox := (player.position - now) * Vector3(1, 0, 1)
	assert_float(facing.dot(to_fox.normalized())).is_greater(0.9)  # it looks at the fox
	assert_float(Vector2(now.x - otter.x, now.z - otter.z).length()).is_less(3.0)  # stays
	player.position = now + Vector3(3.5, 0.0, 0.0)  # closer than it likes, but slowly
	system.tick(0.0)
	_step(system, 4.0)
	var after := system.position_of(i)
	var gap := Vector2(after.x - player.position.x, after.z - player.position.z).length()
	assert_float(gap).is_greater(3.5)  # it backed off…
	assert_float(gap).is_less(OTTER.curious_radius + 4.0)  # …without fleeing far


func test_a_rushing_fox_makes_it_dive_and_come_up_out_of_reach() -> void:
	var made := _system(_lake)
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	var i := _swimming_otter(system)
	var otter := system.position_of(i)
	player.position = otter + Vector3(6.0, 0.0, 0.0)
	system.tick(0.0)
	var step := 1.0 / SETTINGS.sim_hz
	for t in 6:  # swimming at it, fast
		player.position += Vector3(-0.2, 0.0, 0.0)
		system.tick(step)
		system.advance_hops(step)
	assert_int(system.state_of(i)).is_equal(CritterSystem.State.UNDER)
	assert_bool(system.is_shown(i)).is_false()
	_step(system, OTTER.dive_seconds.y + 1.0)
	assert_bool(system.is_shown(i)).is_true()
	var up := system.position_of(i)
	var gap := Vector2(up.x - player.position.x, up.z - player.position.z).length()
	assert_float(gap).is_greater(OTTER.startle_radius)


# The first otter den of the lake ring.
func _den() -> IslandTreasure:
	var sampler := HeightSampler.new(TERRAIN, SEED)
	var start := Places.band_start(TERRAIN, sampler, &"lakes")
	var size := TERRAIN.islands.cell_size
	for a in 360:
		var p := Vector2.from_angle(a * TAU / 360.0) * (start + 400.0)
		var cell := Vector2i((p / size).floor())
		var found := IslandPlan.treasure(cell, TERRAIN.islands, sampler, SEED, TERRAIN.sea_level)
		if found != null and found.kind == IslandPlan.Treasure.OTTER_DEN:
			return found
	return null


func test_a_family_lives_at_each_otter_den() -> void:
	var den := _den()
	assert_object(den).is_not_null()
	var none: CritterKind = OTTER.duplicate()
	none.chance = 0.0  # only the den's family
	var system: CritterSystem = _system(Vector2(den.centre.x, den.centre.z), none, 2)[0]
	assert_int(system.count()).is_between(OTTER.den_family.x, OTTER.den_family.y)
	for i in system.count():
		var at := GameState.absolute_position(system.position_of(i))
		assert_float(Vector2(at.x - den.centre.x, at.z - den.centre.z).length()).is_less(85.0)
	var again: CritterSystem = _system(Vector2(den.centre.x, den.centre.z), none, 2)[0]
	assert_vector(again.position_of(0)).is_equal(system.position_of(0))  # deterministic


func test_the_journal_has_the_otter_of_the_lakes() -> void:
	var entry := JOURNAL.entry(&"otter")
	assert_object(entry).is_not_null()
	assert_object(entry.animal).is_equal(OTTER)
	assert_array(entry.biome_ids(TERRAIN.biomes)).contains([&"lakes"])
	assert_str(String(ProceduralMeshes.critter(&"otter").resource_name)).is_not_null()
	var size := ProceduralMeshes.critter(&"otter").get_aabb().size
	assert_float(size.z).is_between(0.8, 1.1)  # nose to tail tip ≈ 1 m
	assert_float(size.y).is_less(0.3)  # long and low
