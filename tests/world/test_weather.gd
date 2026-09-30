## Tests for the weather: the Markov chain ([WeatherModel]) and the [Weather] node (easing,
## wetting and drying, events, sky and sunlight).
extends GdUnitTestSuite

const SETTINGS: WeatherSettings = preload("res://data/world/weather.tres")
const SEED: int = 12345

var _saved_minutes: float
var _saved_seed: int


func before_test() -> void:
	_saved_minutes = GameState.game_minutes
	_saved_seed = GameState.world_seed
	GameState.world_seed = SEED


func after_test() -> void:
	GameState.game_minutes = _saved_minutes
	GameState.world_seed = _saved_seed


func _model(world_seed: int = SEED) -> WeatherModel:
	return WeatherModel.new(world_seed, SETTINGS.transitions())


## First slot ≥ [param from] in state [param wanted].
func _find(model: WeatherModel, wanted: int, from: int = 1) -> int:
	for slot in range(from, from + 2000):
		if model.state_at(slot) == wanted:
			return slot
	return -1


func test_settings_are_valid_and_it_never_rains_from_a_clear_sky() -> void:
	assert_array(Array(SETTINGS.get_validation_errors())).is_empty()
	var model := _model()
	for slot in range(1, 5000):
		if model.state_at(slot - 1) == WeatherModel.Kind.CLEAR:
			assert_int(model.state_at(slot)).is_not_equal(WeatherModel.Kind.RAIN)


func test_the_same_time_brings_the_same_weather() -> void:
	var a := _model()
	var b := _model()
	for slot in [5, 200, 17, 1000, 3]:  # out of order: the cache must not matter
		assert_int(a.state_at(slot)).is_equal(b.state_at(slot))
	var other := _model(SEED + 1)
	var differs := false
	for slot in 200:
		differs = differs or other.state_at(slot) != a.state_at(slot)
	assert_bool(differs).is_true()


func test_rain_about_fifteen_percent_of_the_time_in_episodes_of_a_few_slots() -> void:
	var model := _model()
	var counts := [0, 0, 0]
	var episodes := 0
	var n := 20000
	for slot in range(1, n + 1):
		var s := model.state_at(slot)
		counts[s] += 1
		if s == WeatherModel.Kind.RAIN and model.state_at(slot - 1) != WeatherModel.Kind.RAIN:
			episodes += 1
	var rain_fraction := float(counts[WeatherModel.Kind.RAIN]) / n
	assert_float(rain_fraction).is_between(0.12, 0.18)
	assert_float(float(counts[WeatherModel.Kind.CLOUDY]) / n).is_greater(0.3)  # often cloudy
	var mean_episode := float(counts[WeatherModel.Kind.RAIN]) / episodes
	assert_float(mean_episode).is_between(3.0, 5.0)  # slots of 1 game hour = 1 real minute


func _weather() -> Weather:
	var weather: Weather = auto_free(Weather.new())
	weather.settings = SETTINGS
	add_child(weather)
	weather.set_process(false)
	return weather


func test_eases_into_rain_wets_the_ground_and_dries_afterwards() -> void:
	var model := _model()
	var rain_slot := _find(model, WeatherModel.Kind.RAIN, 10)
	GameState.game_minutes = (rain_slot - 1) * SETTINGS.slot_minutes  # just before the rain
	var weather := _weather()
	weather.advance(0.0)
	var before := weather.rain
	GameState.game_minutes = rain_slot * SETTINGS.slot_minutes
	weather.advance(1.0)
	assert_int(weather.state()).is_equal(WeatherModel.Kind.RAIN)
	assert_float(weather.rain).is_less_equal(before + SETTINGS.ease_per_minute + 1e-4)  # eases
	for i in 60:
		weather.advance(1.0)
	assert_float(weather.rain).is_equal(1.0)
	assert_float(weather.wetness).is_greater(0.9)
	var clear_slot := _find(model, WeatherModel.Kind.CLEAR, rain_slot)
	GameState.game_minutes = clear_slot * SETTINGS.slot_minutes
	for i in 60:
		weather.advance(1.0)
	assert_float(weather.rain).is_equal(0.0)
	var wet_after_an_hour := weather.wetness
	assert_float(wet_after_an_hour).is_between(0.0, 0.9)  # drying, slowly
	for i in 200:
		weather.advance(1.0)
	assert_float(weather.wetness).is_equal(0.0)


func test_publishes_the_weather_and_signals_changes() -> void:
	var model := _model()
	var rain_slot := _find(model, WeatherModel.Kind.RAIN, 10)
	var seen: Array[StringName] = []
	var on_changed := func(w: StringName) -> void: seen.append(w)
	EventBus.weather_changed.connect(on_changed)
	GameState.game_minutes = rain_slot * SETTINGS.slot_minutes
	var weather := _weather()
	weather.advance(0.0)
	weather.advance(1.0)  # same slot: no new event
	EventBus.weather_changed.disconnect(on_changed)
	assert_array(seen).contains_exactly([&"rain"])
	assert_str(String(GameState.weather)).is_equal("rain")
	assert_float(weather.rain).is_equal(1.0)  # starts settled, not easing in


func test_clouds_dim_the_sun_and_cover_the_sky() -> void:
	var world_environment: WorldEnvironment = auto_free(WorldEnvironment.new())
	world_environment.environment = Environment.new()
	add_child(world_environment)
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	add_child(sun)
	var cycle: DayNightCycle = auto_free(DayNightCycle.new())
	cycle.settings = load("res://data/world/day_night.tres")
	cycle.sun = sun
	cycle.world_environment = world_environment
	add_child(cycle)
	cycle.apply_hour(12.0)
	var clear_energy := sun.light_energy
	var model := _model()
	GameState.game_minutes = _find(model, WeatherModel.Kind.RAIN, 10) * SETTINGS.slot_minutes
	var weather := _weather()
	weather.day_night = cycle
	weather.advance(0.0)
	cycle.apply_hour(12.0)
	assert_float(cycle.sky_material().get_shader_parameter(&"cloud_cover")).is_equal(
		SETTINGS.cloudiness[WeatherModel.Kind.RAIN]
	)
	assert_float(sun.light_energy).is_less(clear_energy * 0.7)
