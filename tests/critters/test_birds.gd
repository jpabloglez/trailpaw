## Tests for the songbirds ([BirdFlocks]): deterministic flocks per chunk and biome, perched on
## the ground or on real treetops, moving on by day, scattering from a running (not a walking)
## fox, roosting at night, and the birdsong following perched birds near the listener.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const BIRDS: BirdSettings = preload("res://data/critters/birds.tres")
const AMBIENCE: AmbienceSettings = preload("res://data/audio/ambience.tres")
const SEED: int = 12345
const MEADOW_BIRDS := 0

var _saved_seed: int
var _saved_water: float
var _saved_minutes: float
var _saved_biome: StringName


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_water = GameState.water_level
	_saved_minutes = GameState.game_minutes
	_saved_biome = GameState.current_biome
	GameState.world_seed = SEED
	GameState.water_level = TERRAIN.sea_level
	GameState.game_minutes = 12.0 * 60.0


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.water_level = _saved_water
	GameState.game_minutes = _saved_minutes
	GameState.current_biome = _saved_biome


func _coords(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			out.append(Vector2i(x, z))
	return out


func _flocks(settings: BirdSettings = BIRDS) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	player.position = Vector3(10000, 0, 10000)
	add_child(player)
	var flocks: BirdFlocks = auto_free(BirdFlocks.new())
	flocks.settings = settings
	flocks.terrain = TERRAIN
	flocks.player = player
	add_child(flocks)
	flocks.set_physics_process(false)
	flocks.set_process(false)
	return [flocks, player]


func _run(flocks: BirdFlocks, seconds: float) -> void:
	var step := 1.0 / BirdFlocks.TICK_HZ
	for i in int(seconds * BirdFlocks.TICK_HZ):
		flocks.tick(step)
		flocks.advance(step)


func _flock_centre(flocks: BirdFlocks, f: int) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in flocks.count():
		if flocks._b_flock[b] == f:
			sum += flocks.perch_of(b)
			n += 1
	return sum / n


func test_flocks_are_deterministic_and_biome_bound() -> void:
	var a := BirdFlocks.roll(Vector2i(4, 7), &"forest", BIRDS, SEED, 64.0)
	assert_that(a).is_equal(BirdFlocks.roll(Vector2i(4, 7), &"forest", BIRDS, SEED, 64.0))
	var forest := 0
	var hills := 0
	for i in 400:
		var coord := Vector2i(i % 20, i / 20)
		var flock := BirdFlocks.roll(coord, &"forest", BIRDS, SEED, 64.0)
		if not flock.is_empty():
			forest += 1
			assert_int(int(flock[0])).is_between(BIRDS.flock_size.x, BIRDS.flock_size.y)
		hills += int(not BirdFlocks.roll(coord, &"hills", BIRDS, SEED, 64.0).is_empty())
	assert_float(forest / 400.0).is_between(0.45, 0.65)
	assert_int(hills).is_less(forest)


func test_flocks_perch_on_the_ground_without_trees() -> void:
	var flocks: BirdFlocks = _flocks()[0]
	flocks.sync(_coords(3))
	assert_int(flocks.flock_count()).is_greater(0)
	var sampler := HeightSampler.new(TERRAIN, SEED)
	for b in flocks.count():
		var at := flocks.position_of(b)
		var ground := maxf(sampler.height_at(at.x, at.z), TERRAIN.sea_level + 0.1)
		assert_float(at.y).is_equal_approx(ground, 0.05)
	for f in flocks.flock_count():
		assert_int(flocks.flock_state(f)).is_equal(BirdFlocks.State.PERCHED)


func test_by_day_they_move_on_and_land_elsewhere() -> void:
	var flocks: BirdFlocks = _flocks()[0]
	flocks.sync(_coords(3))
	var before := _flock_centre(flocks, 0)
	var flew := false
	var step := 1.0 / BirdFlocks.TICK_HZ
	for i in int((BIRDS.perch_seconds.y + 15.0) * BirdFlocks.TICK_HZ):
		flocks.tick(step)
		flocks.advance(step)
		flew = flew or flocks.flock_state(0) == BirdFlocks.State.FLYING
	assert_bool(flew).is_true()
	_run(flocks, 10.0)
	assert_int(flocks.flock_state(0)).is_equal(BirdFlocks.State.PERCHED)
	assert_float(_flock_centre(flocks, 0).distance_to(before)).is_greater(
		BIRDS.move_distance.x * 0.5
	)


func _approach(flocks: BirdFlocks, player: Node3D, speed: float, seconds: float) -> void:
	var target := _flock_centre(flocks, 0)
	var step := 1.0 / BirdFlocks.TICK_HZ
	for i in int(seconds * BirdFlocks.TICK_HZ):
		var to := Vector3(target.x - player.position.x, 0.0, target.z - player.position.z)
		if to.length() > 2.0:
			player.position += to.normalized() * speed * step
		flocks.tick(step)
		flocks.advance(step)


func test_a_running_fox_scatters_the_flock() -> void:
	var made := _flocks()
	var flocks: BirdFlocks = made[0]
	var player: Node3D = made[1]
	flocks.sync(_coords(3))
	var centre := _flock_centre(flocks, 0)
	player.position = centre + Vector3(10.0, 0.0, 0.0)
	flocks.tick(0.0)
	_approach(flocks, player, 7.5, 1.0)
	assert_int(flocks.flock_state(0)).is_equal(BirdFlocks.State.FLYING)
	var away := _flock_centre(flocks, 0)
	(
		assert_float(Vector2(away.x - player.position.x, away.z - player.position.z).length())
		. is_greater(BIRDS.flee_distance.x * 0.6)
	)


func test_a_walking_fox_does_not() -> void:
	var made := _flocks()
	var flocks: BirdFlocks = made[0]
	var player: Node3D = made[1]
	var calm := BIRDS.duplicate() as BirdSettings
	calm.perch_seconds = Vector2(500, 600)  # no calm moves during the test
	flocks.settings = calm
	flocks.sync(_coords(3))
	player.position = _flock_centre(flocks, 0) + Vector3(8.0, 0.0, 0.0)
	flocks.tick(0.0)
	_approach(flocks, player, 1.1, 5.0)
	assert_int(flocks.flock_state(0)).is_equal(BirdFlocks.State.PERCHED)


func test_at_night_they_roost_and_are_silent() -> void:
	var flocks: BirdFlocks = _flocks()[0]
	var cycle: DayNightCycle = auto_free(DayNightCycle.new())
	cycle.settings = load("res://data/world/day_night.tres")
	flocks.day_night = cycle
	GameState.game_minutes = 1.0 * 60.0  # 01:00
	flocks.sync(_coords(3))
	_run(flocks, BIRDS.perch_seconds.y + 10.0)
	for f in flocks.flock_count():
		assert_int(flocks.flock_state(f)).is_equal(BirdFlocks.State.PERCHED)
	assert_float(flocks.presence(_flock_centre(flocks, 0))).is_equal(0.0)


func test_birdsong_needs_birds_near_and_perched() -> void:
	var flocks: BirdFlocks = _flocks()[0]
	flocks.sync(_coords(3))
	var near := _flock_centre(flocks, 0)
	assert_float(flocks.presence(near)).is_greater(0.5)
	assert_float(flocks.presence(near + Vector3(BIRDS.song_radius * 4.0, 0, 0))).is_equal(0.0)
	var before := flocks.presence(near)
	flocks._take_off(0, near + Vector3(3, 0, 0))  # in the air: not singing
	flocks.advance(0.1)
	assert_float(flocks.presence(near)).is_less(before)


func test_the_ambience_birdsong_follows_the_birds() -> void:
	var flocks: BirdFlocks = _flocks()[0]
	var director: AmbienceDirector = auto_free(AmbienceDirector.new())
	director.settings = AMBIENCE
	director.birds = flocks
	add_child(director)
	director.set_process(false)
	GameState.current_biome = &"meadow"
	director.advance(120.0)  # long enough for spells to come and go: never any birdsong
	assert_float(director.volume(MEADOW_BIRDS)).is_equal(0.0)
	flocks.sync(_coords(3))
	var listener: Node3D = auto_free(Node3D.new())
	listener.add_to_group(Animal.PLAYER_GROUP)
	add_child(listener)
	listener.global_position = _flock_centre(flocks, 0)
	var loudest := 0.0
	for i in 600:
		director.advance(0.5)
		loudest = maxf(loudest, director.volume(MEADOW_BIRDS))
	assert_float(loudest).is_greater(0.1)


func test_treetops_are_real_trees() -> void:
	var settings := TERRAIN
	var library := VegetationLibrary.new(settings.biomes)
	var data := ChunkGenerator.generate_with(
		Vector2i(17, 2),
		0,
		settings,
		HeightSampler.new(settings, SEED),
		VegetationScatterer.new(settings.biomes),
		SEED
	)
	var chunk: TerrainChunk = auto_free(load("res://scenes/world/terrain_chunk.tscn").instantiate())
	add_child(chunk)
	chunk.apply(data, load("res://data/world/terrain_material.tres"), library)
	var tops := PackedVector3Array()
	chunk.spots(&"tree_top", tops)
	assert_int(tops.size()).is_greater(5)
	var origins := {}
	for id: StringName in data.vegetation:
		if library.shade_for(id) > 0.0:
			var buffer: PackedFloat32Array = data.vegetation[id]
			for o in range(0, buffer.size(), VegetationScatterer.FLOATS_PER_INSTANCE):
				origins[Vector2(buffer[o + 3], buffer[o + 11])] = buffer[o + 7]
	for top in tops:
		var key := Vector2(top.x, top.z)
		assert_bool(origins.has(key)).is_true()
		assert_float(top.y).is_greater(float(origins[key]) + 1.0)  # up in the crown


func test_a_full_sky_fits_the_budget() -> void:
	var busy := BIRDS.duplicate() as BirdSettings
	busy.biome_chance = {&"meadow": 1.0, &"forest": 1.0, &"hills": 1.0, &"river_valley": 1.0}
	var flocks: BirdFlocks = _flocks(busy)[0]
	flocks.sync(_coords(5))
	assert_int(flocks.count()).is_greater(BIRDS.max_birds - BIRDS.flock_size.y)
	for f in flocks.flock_count():
		flocks._take_off(f, Vector3.INF)
	var times := PackedFloat32Array()
	for i in 60:
		var start := Time.get_ticks_usec()
		flocks.tick(1.0 / BirdFlocks.TICK_HZ)
		flocks.advance(1.0 / 60.0)
		flocks.draw()
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	assert_float(times[times.size() / 2]).is_less(2.0)
