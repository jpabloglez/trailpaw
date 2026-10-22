## Tests for the beavers (Phase 19): each group lives at its lodge, a mound of sticks on the
## waterline with deep water beside it; left alone they swim to the shore, gnaw, carry a stick
## home and go into the lodge; startled they slap their tails and dive in, staying there while
## the fox is about; the lodges come and go with their chunks and block the fox.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const BEAVER: CritterKind = preload("res://data/critters/beaver.tres")
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
	system.kinds = [BEAVER] as Array[CritterKind]
	system.settings = SETTINGS
	system.terrain = TERRAIN
	system.player = player
	add_child(system)
	system.set_physics_process(false)
	system.set_process(false)
	system.sync(_chunks(around, reach))
	return [system, player]


func _chunks(around: Vector2, reach: int) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	var centre := Vector2i((around / TERRAIN.chunk_size).floor())
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			chunks.append(centre + Vector2i(x, z))
	return chunks


func _step(system: CritterSystem, seconds: float) -> void:
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(seconds * SETTINGS.sim_hz):
		system.tick(step)
		system.advance_hops(step)


func _ground(at: Vector3) -> float:
	var abs := GameState.absolute_position(at)
	return HeightSampler.new(TERRAIN, SEED).height_at(abs.x, abs.z)


# The lodge nearest to local [param at].
func _lodge_near(system: CritterSystem, at: Vector3) -> Vector3:
	var best := Vector3.INF
	for l in system.lodges().count():
		var place := system.lodges().place_of(l)
		if best == Vector3.INF or place.distance_to(at) < best.distance_to(at):
			best = place
	return best


func test_each_group_lives_at_its_lodge_on_the_waterline() -> void:
	var system: CritterSystem = _system()[0]
	var lodges := system.lodges()
	assert_int(lodges.count()).is_greater(1)
	assert_int(system.count()).is_greater_equal(lodges.count() * 2)
	for l in lodges.count():
		var place := lodges.place_of(l)
		assert_float(place.y - TERRAIN.sea_level).is_between(-0.7, 0.4)
		var wet := false
		for d in 8:
			var spot := place + Vector3.FORWARD.rotated(Vector3.UP, d * TAU / 8.0) * 4.0
			wet = wet or _ground(spot) <= TERRAIN.sea_level - BEAVER.min_depth
		assert_bool(wet).is_true()
		assert_int(lodges.body_of(l).collision_layer).is_equal(1)  # the fox goes round it
	for i in system.count():
		var lodge := _lodge_near(system, system.position_of(i))
		(
			assert_float(
				(
					Vector2(system.position_of(i).x - lodge.x, system.position_of(i).z - lodge.z)
					. length()
				)
			)
			. is_less_equal(maxf(BEAVER.group_spread, 4.0) + 0.01)
		)  # its group, or by the lodge
	var meadow: CritterSystem = _system(Vector2(250.0, -720.0), 3)[0]  # no beavers by the meadow
	assert_int(meadow.lodges().count()).is_equal(0)


func test_left_alone_they_fetch_sticks_from_the_shore_and_take_them_home() -> void:
	var system: CritterSystem = _system()[0]
	var ashore := false
	var carrying := false
	var inside := false
	var homes := PackedVector3Array()
	for i in system.count():
		homes.append(_lodge_near(system, system.position_of(i)))
	for second in 300:
		_step(system, 1.0)
		for i in system.count():
			var at := system.position_of(i)
			ashore = ashore or not system.is_swimming(i)
			carrying = carrying or system.pose_of(i) == CritterSystem.Pose.CARRYING
			inside = inside or system.state_of(i) == CritterSystem.State.UNDER
			var home := homes[i]
			assert_float(Vector2(at.x - home.x, at.z - home.z).length()).is_less(
				BEAVER.home_radius + 6.0
			)
	assert_bool(ashore).is_true()
	assert_bool(carrying).is_true()
	assert_bool(inside).is_true()


func test_startled_it_slaps_its_tail_and_stays_in_the_lodge_while_the_fox_is_about() -> void:
	var made := _system()
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	var i := -1
	for b in system.count():
		if system.is_swimming(b) and system.is_shown(b):
			i = b
			break
	var beaver := system.position_of(i)
	var lodge := _lodge_near(system, beaver)
	player.position = beaver + Vector3(8.0, 0.0, 0.0)
	system.tick(0.0)
	var step := 1.0 / SETTINGS.sim_hz
	for t in 8:  # coming at it fast
		player.position += Vector3(-0.15, 0.0, 0.0)
		system.tick(step)
		system.advance_hops(step)
	assert_int(system.slaps).is_greater_equal(1)
	assert_int(system.state_of(i)).is_equal(CritterSystem.State.UNDER)
	_step(system, BEAVER.dive_seconds.y + 2.0)
	assert_bool(system.is_shown(i)).is_false()  # the fox is still here
	player.position = beaver + Vector3(80.0, 0.0, 0.0)
	_step(system, 4.0)
	assert_bool(system.is_shown(i)).is_true()
	var out := system.position_of(i)
	assert_float(Vector2(out.x - lodge.x, out.z - lodge.z).length()).is_less_equal(5.01)


func test_lodges_come_and_go_with_their_chunks_and_follow_rebases() -> void:
	var system: CritterSystem = _system()[0]
	var lodges := system.lodges()
	var before := lodges.count()
	var place := lodges.place_of(0)
	var body := lodges.body_of(0)
	EventBus.origin_shifted.emit(Vector3(64, 0, -64))
	assert_vector(lodges.place_of(0)).is_equal(place - Vector3(64, 0, -64))
	assert_vector(body.position - Vector3.UP * BeaverLodges.HEIGHT * 0.25).is_equal_approx(
		lodges.place_of(0), Vector3.ONE * 1e-4
	)
	EventBus.origin_shifted.emit(Vector3(-64, 0, 64))
	system.sync([] as Array[Vector2i])
	assert_int(lodges.count()).is_equal(0)
	await get_tree().process_frame
	assert_bool(is_instance_valid(body)).is_false()
	system.sync(_chunks(_lake, 6))
	assert_int(lodges.count()).is_equal(before)  # the same lodges again
	assert_vector(lodges.place_of(0)).is_equal(place)


func test_the_slap_is_a_sharp_crack() -> void:
	var slap := SynthSounds.slap()
	assert_float(slap.get_length()).is_between(0.3, 0.6)
	var early := 0
	var late := 0
	for i in range(0, slap.data.size(), 2):
		var sample := absi(slap.data.decode_s16(i))
		if i < 2 * int(SynthSounds.RATE * 0.01):
			early = maxi(early, sample)
		elif i > 2 * int(SynthSounds.RATE * 0.3):
			late = maxi(late, sample)
	assert_int(early).is_greater(late * 4)  # loud at once, then dying away


func test_the_journal_has_the_beaver_and_the_meshes_have_their_size() -> void:
	var entry := JOURNAL.entry(&"beaver")
	assert_object(entry).is_not_null()
	assert_object(entry.animal).is_equal(BEAVER)
	assert_array(entry.biome_ids(TERRAIN.biomes)).contains([&"lakes"])
	var beaver := ProceduralMeshes.critter(&"beaver").get_aabb().size
	assert_float(beaver.z).is_between(0.6, 0.85)  # nose to paddle
	var lodge := ProceduralMeshes.lodge().get_aabb()
	assert_float(lodge.size.x).is_between(2.6, 3.6)
	assert_float(lodge.end.y).is_between(1.0, 1.5)
