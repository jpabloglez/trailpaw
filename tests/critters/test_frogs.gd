## Tests for frogs, the critter layer's amphibians: they live on the banks, leap into the water
## with a plop when the fox runs at them, stay under for a while and come back up on a bank
## away from it; and their chorus is heard at night in the wetland.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const FROG: CritterKind = preload("res://data/critters/frog.tres")
const AMBIENCE: AmbienceSettings = preload("res://data/audio/ambience.tres")
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
	system.kinds = [FROG] as Array[CritterKind]
	system.settings = SETTINGS
	system.terrain = TERRAIN
	system.player = player
	add_child(system)
	system.set_physics_process(false)
	system.set_process(false)
	return [system, player]


# Syncs [param coords] and ticks until every chunk's amphibians have spawn (one per tick).
func _sync(system: CritterSystem, coords: Array[Vector2i]) -> void:
	system.sync(coords)
	for c in coords.size():
		system.tick(0.0)


func _run(
	system: CritterSystem, seconds: float, player: Node3D = null, chase: Vector3 = Vector3.INF
) -> void:
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(seconds * SETTINGS.sim_hz):
		if player != null and chase != Vector3.INF:
			player.position += (chase - player.position).normalized() * 7.5 * step
		system.tick(step)
		system.advance_hops(step)


func _assert_on_banks(system: CritterSystem) -> void:
	var sampler := HeightSampler.new(TERRAIN, SEED)
	for i in system.count():
		if system.state_of(i) == CritterSystem.State.UNDER:
			continue
		var at := system.position_of(i)
		var height := sampler.height_at(at.x, at.z) - TERRAIN.sea_level
		assert_float(height).is_between(-0.06, FROG.bank_height + 0.01)
		var deepest := INF  # water to dive into close by
		for d in 16:
			for reach: float in [1.0, 2.0]:
				var spot := at + Vector3(cos(d * TAU / 16.0), 0.0, sin(d * TAU / 16.0)) * reach
				deepest = minf(deepest, sampler.height_at(spot.x, spot.z))
		assert_float(deepest).is_less_equal(TERRAIN.sea_level - FROG.min_depth)


func test_frogs_spawn_after_the_other_critters_one_chunk_per_tick() -> void:
	var system: CritterSystem = _system()[0]
	var coords := _around(WETLAND_CHUNK, 2)
	system.sync(coords)
	assert_int(system.count_of(&"frog")).is_equal(0)  # rolled later, spread over ticks
	_sync(system, [] as Array[Vector2i])
	for c in coords.size():
		system.tick(0.0)
	assert_int(system.count_of(&"frog")).is_equal(0)  # their chunks are gone: nothing rolls
	_sync(system, coords)
	assert_int(system.count_of(&"frog")).is_greater(0)


func test_frogs_live_on_the_banks_of_the_wetland() -> void:
	var system: CritterSystem = _system()[0]
	_sync(system, _around(WETLAND_CHUNK, 2))
	assert_int(system.count()).is_greater(10)
	_assert_on_banks(system)
	_run(system, 30.0)  # hopping about keeps them on the banks
	_assert_on_banks(system)
	var dry: CritterSystem = _system()[0]
	_sync(dry, _around(Vector2i.ZERO, 1))  # the spawn meadow has neither banks nor frogs
	assert_int(dry.count()).is_equal(0)


func test_a_running_fox_makes_a_frog_dive_and_come_back_up_on_a_bank() -> void:
	var tried := 0
	for pick in 5:  # five different frogs, each in a fresh system
		var made := _system()
		var system: CritterSystem = made[0]
		var player: Node3D = made[1]
		_sync(system, _around(WETLAND_CHUNK, 2))
		if pick >= system.count():
			break
		var i := pick  # every frog has water to dive into within 2 m (see _assert_on_banks)
		tried += 1
		var frog := system.position_of(i)
		player.position = frog + Vector3(4.0, 0.0, 0.0)
		system.tick(0.0)
		_run(system, 0.8, player, frog)
		assert_int(system.plops).is_greater(0)
		assert_int(system.state_of(i)).is_equal(CritterSystem.State.UNDER)
		var under := system.position_of(i)
		system.draw()  # under the water it is not drawn
		var drawn: MultiMesh = system.get_child(0).multimesh
		assert_int(drawn.visible_instance_count).is_less(system.count())
		_run(system, FROG.dive_seconds.y + 2.0)
		assert_int(system.state_of(i)).is_not_equal(CritterSystem.State.UNDER)
		var back := system.position_of(i)
		assert_float(Vector2(back.x - under.x, back.z - under.z).length()).is_between(1.4, 8.1)
		var from_fox := Vector2(back.x - player.position.x, back.z - player.position.z).length()
		assert_float(from_fox).is_greater_equal(FROG.startle_radius * 2.0)  # not startled again
		_assert_on_banks(system)
	assert_int(tried).is_equal(5)


func test_their_chorus_is_a_night_sound_of_the_wetland() -> void:
	var chorus: AmbienceLayer = null
	for layer in AMBIENCE.layers:
		if layer.stream.resource_path.ends_with("frog_chorus.wav"):
			chorus = layer
	assert_object(chorus).is_not_null()
	var night := chorus.volume_for(&"wetland", 0.0, 0.0)
	assert_float(night).is_greater(0.2)
	assert_float(chorus.volume_for(&"wetland", 1.0, 0.0)).is_less(night * 0.2)
	assert_float(chorus.volume_for(&"river_valley", 0.0, 0.0)).is_between(0.01, night)
	for biome: StringName in [&"meadow", &"forest", &"hills"]:
		assert_float(chorus.volume_for(biome, 0.0, 0.0)).is_equal(0.0)


func test_the_plop_is_short_and_audible() -> void:
	var plop := SynthSounds.plop()
	assert_float(plop.get_length()).is_between(0.1, 0.25)
	var loudest := 0
	for i in range(0, plop.data.size(), 2):
		loudest = maxi(loudest, absi(plop.data.decode_s16(i)))
	assert_int(loudest).is_greater(8000)
