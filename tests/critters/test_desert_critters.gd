## Tests for the desert's small animals (Phase 18): lizards that bask by day and, approached,
## dart away and vanish without a sound; desert hares out at dawn and dusk that flee like
## rabbits.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const LIZARD: CritterKind = preload("res://data/critters/lizard.tres")
const HARE: CritterKind = preload("res://data/critters/desert_hare.tres")
const SEED: int = 12345
## Open dunes in the desert (seed 12345, test_height_sampler).
const DUNES := Vector2(-5900.0, -1500.0)

var _saved: Array = []


func before_test() -> void:
	_saved = [
		GameState.world_seed, GameState.water_level, GameState.game_minutes, GameState.snow_line
	]
	GameState.world_seed = SEED
	GameState.water_level = TERRAIN.sea_level
	GameState.snow_line = TERRAIN.snow_line
	GameState.game_minutes = 12.0 * 60.0


func after_test() -> void:
	GameState.world_seed = _saved[0]
	GameState.water_level = _saved[1]
	GameState.game_minutes = _saved[2]
	GameState.snow_line = _saved[3]


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
	var chunks: Array[Vector2i] = []
	var centre := Vector2i((DUNES / TERRAIN.chunk_size).floor())
	for x in range(-5, 6):
		for z in range(-5, 6):
			chunks.append(centre + Vector2i(x, z))
	system.sync(chunks)
	return [system, player]


func _step(system: CritterSystem, seconds: float) -> void:
	var step := 1.0 / SETTINGS.sim_hz
	for t in int(seconds * SETTINGS.sim_hz):
		system.tick(step)
		system.advance_hops(step)


func test_lizards_bask_in_the_desert_by_day() -> void:
	assert_bool(LIZARD.biome_counts.has(&"desert")).is_true()
	assert_bool(LIZARD.is_out(12.0)).is_true()
	assert_bool(LIZARD.is_out(1.0)).is_false()  # asleep in the cold night
	var system: CritterSystem = _system(LIZARD)[0]
	assert_int(system.count()).is_greater(5)


func test_an_approached_lizard_darts_away_and_vanishes_without_a_sound() -> void:
	var made := _system(LIZARD)
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	_step(system, 3.0)
	var lizard := system.position_of(0)
	player.position = lizard + Vector3(5.0, 0.0, 0.0)
	system.tick(0.0)
	for t in 4:  # walking up to it
		player.position += Vector3(-0.3, 0.0, 0.0)
		_step(system, 0.25)
	_step(system, 2.0)  # a quick dash to its hiding place
	assert_int(system.state_of(0)).is_equal(CritterSystem.State.UNDER)
	assert_bool(system.is_shown(0)).is_false()
	assert_int(system.whistles).is_equal(0)  # lizards are silent
	player.position = lizard + Vector3(80.0, 0.0, 0.0)
	_step(system, LIZARD.dive_seconds.y + 2.0)
	assert_bool(system.is_shown(0)).is_true()  # back out once the fox has gone


func test_desert_hares_come_out_at_dusk_and_flee_like_rabbits() -> void:
	assert_bool(HARE.is_out(12.0)).is_false()  # too hot at noon
	assert_bool(HARE.is_out(19.0)).is_true()
	assert_bool(HARE.is_out(6.5)).is_true()
	GameState.game_minutes = 19.0 * 60.0
	var made := _system(HARE)
	var system: CritterSystem = made[0]
	var player: Node3D = made[1]
	assert_int(system.count()).is_greater(1)
	system.tick(0.0)
	var hare := system.position_of(0)
	player.position = hare + Vector3(6.0, 0.0, 0.0)
	system.tick(0.0)
	for t in 4:  # the fox comes running
		player.position += Vector3(-1.2, 0.0, 0.0)
		_step(system, 0.25)
	assert_int(system.state_of(0)).is_equal(CritterSystem.State.FLEE)
	assert_float(system.position_of(0).distance_to(hare)).is_greater(1.0)


func test_lizards_stay_low_where_marmots_sit_up() -> void:
	var marmot: CritterKind = load("res://data/critters/marmot.tres")
	var lizards: CritterSystem = _system(LIZARD)[0]
	var sat_up := false
	for moment in 16:  # across the marmots' 7 s watch cycle
		lizards._time = moment * 0.5
		var scale := lizards.basis_of(0).get_scale()
		assert_float(scale.y / scale.x).is_equal_approx(1.0, 1e-3)
		var as_marmot := lizards.basis_of(0)
		lizards.kinds[0] = marmot  # the same animal, as a marmot, would sit up
		as_marmot = lizards.basis_of(0)
		lizards.kinds[0] = LIZARD
		sat_up = sat_up or as_marmot.get_scale().y / as_marmot.get_scale().x > 1.3
	assert_bool(sat_up).is_true()
