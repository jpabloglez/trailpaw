## Tests for the morning mist: none at midday or away from the wetland, thickest at dawn there,
## fading in smoothly across the biome border and over time, lighter on Low, and leaving the
## environment's own fog untouched when there is none.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const MIST: MistSettings = preload("res://data/world/mist.tres")
const MEDIUM: QualityPreset = preload("res://data/quality/medium.tres")
const LOW: QualityPreset = preload("res://data/quality/low.tres")
const SEED: int = 12345

var _saved_seed: int
var _saved_minutes: float
var _saved_quality: QualityPreset
var _resolver: BiomeResolver


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_minutes = GameState.game_minutes
	_saved_quality = Settings.quality
	GameState.world_seed = SEED
	Settings.set_quality(MEDIUM)
	_resolver = BiomeResolver.new(TERRAIN.biomes, SEED)


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.game_minutes = _saved_minutes
	Settings.set_quality(_saved_quality)


func _mist(at: Vector3) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	player.global_position = at
	var environment := Environment.new()
	environment.fog_depth_begin = 90.0
	environment.fog_depth_end = 200.0
	var world: WorldEnvironment = auto_free(WorldEnvironment.new())
	world.environment = environment
	var cycle: DayNightCycle = auto_free(DayNightCycle.new())  # not in the tree: fields only
	var mist: Mist = auto_free(Mist.new())
	mist.settings = MIST
	mist.terrain = TERRAIN
	mist.world_environment = world
	mist.day_night = cycle
	mist.player = player
	add_child(mist)
	mist.set_process(false)
	return [mist, environment, cycle, player]


# A point on the z = 0 line whose blend is all [param id] (searching east from [param from]).
func _inside(id: StringName, from: float) -> Vector3:
	for x in range(int(from), int(from) + 4000, 10):
		var weights := _resolver.weights_at(x, 0.0)
		if weights.get(id, 0.0) >= 0.999:
			return Vector3(x, 0.0, 0.0)
	return Vector3.INF


func _settle(mist: Mist) -> void:
	for i in 100:  # 10 s at 10 Hz: long enough to reach the target
		mist.step(0.1)


func test_thickest_at_dawn_in_the_wetland() -> void:
	var wetland := _inside(&"wetland", 0.0)
	assert_vector(wetland).is_not_equal(Vector3.INF)
	var made := _mist(wetland)
	var mist: Mist = made[0]
	var environment: Environment = made[1]
	var cycle: DayNightCycle = made[2]
	GameState.game_minutes = 6.5 * 60.0
	_settle(mist)
	assert_float(mist.amount()).is_equal_approx(1.0, 1e-4)
	assert_float(environment.fog_depth_begin).is_equal_approx(MIST.depth_begin, 1e-3)
	assert_float(environment.fog_depth_end).is_equal_approx(MIST.depth_end, 1e-3)
	assert_float(cycle.mist_amount).is_equal_approx(MIST.color_mix, 1e-4)
	assert_that(cycle.mist_color).is_equal(MIST.color)


func test_none_at_midday_or_away_from_the_water_biomes() -> void:
	var wetland := _inside(&"wetland", 0.0)
	var made := _mist(wetland)
	var mist: Mist = made[0]
	var environment: Environment = made[1]
	var cycle: DayNightCycle = made[2]
	GameState.game_minutes = 6.5 * 60.0
	_settle(mist)
	GameState.game_minutes = 13.0 * 60.0  # it burns off by midday...
	_settle(mist)
	assert_float(mist.amount()).is_equal(0.0)
	assert_float(environment.fog_depth_begin).is_equal(90.0)  # ...back to the own fog exactly
	assert_float(environment.fog_depth_end).is_equal(200.0)
	assert_float(cycle.mist_amount).is_equal(0.0)
	for id: StringName in [&"meadow", &"forest", &"hills"]:  # and dawn elsewhere is clear
		var dry: Mist = _mist(_inside(id, 0.0))[0]
		GameState.game_minutes = 6.5 * 60.0
		_settle(dry)
		assert_float(dry.amount()).override_failure_message(String(id)).is_equal(0.0)
	var valley: Mist = _mist(_inside(&"river_valley", 0.0))[0]  # a little in the valley
	_settle(valley)
	assert_float(valley.amount()).is_equal_approx(MIST.biomes[&"river_valley"], 1e-3)


func test_it_rises_before_dawn_and_burns_off_by_mid_morning() -> void:
	assert_float(MIST.hour_amount(3.0)).is_equal(0.0)
	assert_float(MIST.hour_amount(5.0)).is_between(0.2, 0.8)
	assert_float(MIST.hour_amount(7.0)).is_equal(1.0)
	assert_float(MIST.hour_amount(9.0)).is_between(0.1, 0.6)
	assert_float(MIST.hour_amount(10.0)).is_equal(0.0)
	assert_float(MIST.hour_amount(20.0)).is_equal(0.0)
	assert_array(Array(MIST.get_validation_errors())).is_empty()


func test_it_fades_in_across_the_border_and_over_time() -> void:
	var wetland := _inside(&"wetland", 0.0)
	var made := _mist(wetland - Vector3(400.0, 0.0, 0.0))  # in the valley, before the border
	var mist: Mist = made[0]
	var player: Node3D = made[3]
	GameState.game_minutes = 6.5 * 60.0
	var previous := mist.biome_amount()
	var largest_step := 0.0
	for metres in range(0, 401, 2):  # walking east into the wetland
		player.global_position = wetland - Vector3(400.0 - metres, 0.0, 0.0)
		var now := mist.biome_amount()
		largest_step = maxf(largest_step, absf(now - previous))
		previous = now
	assert_float(previous).is_equal_approx(1.0, 1e-3)
	assert_float(largest_step).is_less(0.05)  # no sudden wall of fog at the border
	var fresh: Mist = _mist(wetland)[0]
	fresh.step(0.1)  # time: it eases in rather than switching on
	assert_float(fresh.amount()).is_less_equal(MIST.response * 0.1 + 1e-6)


func test_lighter_on_low() -> void:
	var mist: Mist = _mist(_inside(&"wetland", 0.0))[0]
	GameState.game_minutes = 6.5 * 60.0
	Settings.set_quality(LOW)
	_settle(mist)
	assert_float(mist.amount()).is_equal_approx(LOW.mist, 1e-4)
	assert_float(LOW.mist).is_less(1.0)
