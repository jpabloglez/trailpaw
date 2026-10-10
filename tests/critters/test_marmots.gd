## Tests for the marmots (Phase 17): they live on the mountain slopes below the snow, graze by
## their burrows, and when the fox comes they whistle, dash home and hide, peeking out again
## once it has gone.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const MARMOT: CritterKind = preload("res://data/critters/marmot.tres")
const SEED: int = 12345
## The foothills-to-crest slope below the peak at (4446.8, −1359.5) (seed 12345).
const SLOPE := Vector2(4200.0, -1290.0)

var _saved: Array = []


func before_test() -> void:
	_saved = [
		GameState.world_seed, GameState.water_level, GameState.game_minutes, GameState.snow_line
	]
	GameState.world_seed = SEED
	GameState.water_level = TERRAIN.sea_level
	GameState.snow_line = TERRAIN.snow_line
	GameState.game_minutes = 12.0 * 60.0  # midday: marmots are out


func after_test() -> void:
	GameState.world_seed = _saved[0]
	GameState.water_level = _saved[1]
	GameState.game_minutes = _saved[2]
	GameState.snow_line = _saved[3]


func _system(kind: CritterKind = MARMOT) -> Array:
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
	var centre := Vector2i((SLOPE / TERRAIN.chunk_size).floor())
	for x in range(-6, 7):
		for z in range(-6, 7):
			chunks.append(centre + Vector2i(x, z))
	system.sync(chunks)
	return [system, player]


func _step(system: CritterSystem, seconds: float) -> void:
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(seconds * SETTINGS.sim_hz):
		system.tick(step)
		system.advance_hops(step)


func test_marmots_live_on_the_mountain_slopes_below_the_snow() -> void:
	assert_bool(MARMOT.biome_counts.keys() == [&"mountains"]).is_true()
	var system: CritterSystem = _system()[0]
	assert_int(system.count()).is_greater(3)
	for i in system.count():
		var at := GameState.absolute_position(system.position_of(i))
		assert_float(at.y).is_less(TERRAIN.snow_line)
		assert_float(at.y).is_greater(TERRAIN.sea_level)


func test_a_scared_marmot_whistles_runs_home_and_hides_then_peeks_out() -> void:
	var made := _system()
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	_step(system, 4.0)  # graze a little away from the burrow
	var marmot := system.position_of(0)
	player.position = marmot + Vector3(12.0, 0.0, 0.0)
	system.tick(0.0)
	for t in 6:  # walking towards it
		player.position += Vector3(-0.3, 0.0, 0.0)
		_step(system, 0.25)
	assert_int(system.whistles).is_greater_equal(1)
	_step(system, 3.0)  # dashing home
	assert_int(system.state_of(0)).is_equal(CritterSystem.State.UNDER)
	assert_bool(system.is_shown(0)).is_false()  # in its burrow: it can't be seen
	_step(system, MARMOT.dive_seconds.y + 2.0)
	assert_bool(system.is_shown(0)).is_false()  # the fox is still here: it stays in
	player.position = marmot + Vector3(60.0, 0.0, 0.0)
	_step(system, 4.0)
	assert_bool(system.is_shown(0)).is_true()  # it peeks out once the fox has gone


func test_a_still_fox_can_watch_them_from_a_distance() -> void:
	var lone: CritterKind = MARMOT.duplicate()  # one per chunk: no neighbour within reach
	lone.biome_counts = {&"mountains": Vector2i(1, 1)} as Dictionary[StringName, Vector2i]
	var made := _system(lone)
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	player.position = system.position_of(0) + Vector3(10.0, 0.0, 0.0)
	system.tick(0.0)
	_step(system, 5.0)  # standing still, beyond the startle radius
	assert_int(system.whistles).is_equal(0)
	assert_bool(system.is_shown(0)).is_true()


func test_the_whistle_is_short_and_high() -> void:
	var whistle := SynthSounds.whistle()
	assert_float(whistle.get_length()).is_between(0.3, 0.7)
	var crossings := 0
	var previous := 0
	for i in range(0, mini(whistle.data.size(), 2 * int(SynthSounds.RATE * 0.1)), 2):
		var sample := whistle.data.decode_s16(i)
		if (sample >= 0) != (previous >= 0):
			crossings += 1
		previous = sample
	assert_int(crossings).is_greater(2 * 200)  # > 2 kHz in the first 0.1 s
