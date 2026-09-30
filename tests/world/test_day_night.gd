## Tests for the day/night cycle: day curves ([DayCurve]), the sun's path, readable nights,
## stars, the moon and the cycle node following the game clock.
extends GdUnitTestSuite

const SETTINGS: DayNightSettings = preload("res://data/world/day_night.tres")

var _saved_minutes: float


func before_test() -> void:
	_saved_minutes = GameState.game_minutes


func after_test() -> void:
	GameState.game_minutes = _saved_minutes


func _cycle() -> DayNightCycle:
	var world_environment: WorldEnvironment = auto_free(WorldEnvironment.new())
	world_environment.environment = Environment.new()
	add_child(world_environment)
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	add_child(sun)
	var cycle: DayNightCycle = auto_free(DayNightCycle.new())
	cycle.settings = SETTINGS
	cycle.sun = sun
	cycle.world_environment = world_environment
	add_child(cycle)
	return cycle


func _luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


# --- curves -------------------------------------------------------------------------------


func test_curves_hit_their_keys_and_interpolate_between_them() -> void:
	var hours := PackedFloat32Array([0.0, 6.0, 12.0, 18.0])
	var values := PackedFloat32Array([0.0, 1.0, 3.0, 1.0])
	assert_float(DayCurve.sample(hours, values, 6.0)).is_equal_approx(1.0, 1e-5)
	assert_float(DayCurve.sample(hours, values, 9.0)).is_equal_approx(2.0, 1e-5)
	assert_float(DayCurve.sample(hours, values, 30.0)).is_equal_approx(1.0, 1e-5)  # wraps days


func test_curves_are_seamless_across_midnight() -> void:
	var hours := PackedFloat32Array([0.0, 6.0, 12.0, 18.0])
	var values := PackedFloat32Array([0.0, 1.0, 3.0, 1.0])
	assert_float(DayCurve.sample(hours, values, 21.0)).is_equal_approx(0.5, 1e-5)
	assert_float(DayCurve.sample(hours, values, 23.999)).is_equal_approx(0.0, 1e-3)


func test_the_settings_are_valid() -> void:
	assert_array(Array(SETTINGS.get_validation_errors())).is_empty()
	var broken := SETTINGS.duplicate() as DayNightSettings
	broken.stars = PackedFloat32Array([1.0])
	assert_bool(broken.is_valid()).is_false()


# --- sun, moon and sky --------------------------------------------------------------------


func test_the_sun_rises_peaks_and_sets_on_time() -> void:
	var cycle := _cycle()
	assert_float(cycle.sun_elevation(SETTINGS.sunrise_hour)).is_equal_approx(0.0, 0.5)
	assert_float(cycle.sun_elevation(SETTINGS.sunset_hour)).is_equal_approx(0.0, 0.5)
	var noon := (SETTINGS.sunrise_hour + SETTINGS.sunset_hour) * 0.5
	assert_float(cycle.sun_elevation(noon)).is_equal_approx(SETTINGS.max_elevation, 0.5)
	assert_float(cycle.sun_elevation(0.0)).is_less(-20.0)  # midnight: well below
	assert_float(cycle.sun_direction(SETTINGS.sunrise_hour + 0.1).x).is_greater(0.9)  # east
	assert_float(cycle.sun_direction(SETTINGS.sunset_hour - 0.1).x).is_less(-0.9)  # west


func test_nights_are_moonlit_and_readable() -> void:
	var cycle := _cycle()
	for hour in [0.0, 2.0, 4.0, 20.5, 22.0, 23.5]:
		cycle.apply_hour(hour)
		var environment := cycle.world_environment.environment
		var ambient := (
			_luminance(environment.ambient_light_color) * environment.ambient_light_energy
		)
		assert_float(ambient).override_failure_message("%.1f h" % hour).is_greater_equal(
			SETTINGS.min_ambient_luminance
		)
		assert_bool(cycle.sun.visible).is_false()
		assert_bool(cycle.moon().visible).is_true()
		assert_float(cycle.moon().light_color.b).is_greater(cycle.moon().light_color.r)  # bluish


func test_days_are_brighter_than_nights_and_the_moon_rests_at_noon() -> void:
	var cycle := _cycle()
	cycle.apply_hour(12.0)
	var noon := _total_light(cycle)
	assert_bool(cycle.sun.visible).is_true()
	assert_bool(cycle.moon().visible).is_false()
	assert_float(cycle.sun.global_basis.z.y).is_greater(0.5)  # it shines downwards
	cycle.apply_hour(0.0)
	assert_float(noon).is_greater(_total_light(cycle) * 2.0)


## Ambient plus direct light (sun or moon, when visible), as luminance × energy.
func _total_light(cycle: DayNightCycle) -> float:
	var environment := cycle.world_environment.environment
	var total := _luminance(environment.ambient_light_color) * environment.ambient_light_energy
	for light: DirectionalLight3D in [cycle.sun, cycle.moon()]:
		if light.visible:
			total += _luminance(light.light_color) * light.light_energy
	return total


func test_stars_only_at_night() -> void:
	var cycle := _cycle()
	cycle.apply_hour(12.0)
	assert_float(cycle.sky_material().get_shader_parameter(&"stars")).is_equal(0.0)
	cycle.apply_hour(1.0)
	assert_float(cycle.sky_material().get_shader_parameter(&"stars")).is_equal(1.0)


func test_the_sky_changes_smoothly_minute_by_minute() -> void:
	var cycle := _cycle()
	var previous := Color.BLACK
	for minute in 24 * 60:
		cycle.apply_hour(minute / 60.0)
		var horizon: Color = cycle.sky_material().get_shader_parameter(&"horizon_color")
		if minute > 0:
			var step := absf(horizon.r - previous.r) + absf(horizon.g - previous.g)
			assert_float(step).override_failure_message("%d min" % minute).is_less(0.03)
		previous = horizon


func test_the_cycle_follows_the_game_clock() -> void:
	var cycle := _cycle()
	GameState.game_minutes = 12 * 60.0
	cycle.apply_now()
	assert_bool(cycle.sun.visible).is_true()
	GameState.game_minutes = 24 * 60.0 * 3 + 60.0  # 01:00 three days later
	cycle.apply_now()
	assert_bool(cycle.sun.visible).is_false()
	assert_object(cycle.world_environment.environment.sky.sky_material).is_same(
		cycle.sky_material()
	)
	assert_int(cycle.world_environment.environment.ambient_light_source).is_equal(
		Environment.AMBIENT_SOURCE_COLOR
	)
