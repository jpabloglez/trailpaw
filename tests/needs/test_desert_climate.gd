## Tests for the desert's climate (Phase 18): hot noons and chilly nights, faster thirst, no
## rain; the savanna is milder, and every other biome is unchanged.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const WEATHER: WeatherSettings = preload("res://data/world/weather.tres")

var _saved: Array = []


func before_test() -> void:
	_saved = [
		GameState.current_biome,
		GameState.game_minutes,
		GameState.weather,
		GameState.water_level,
		GameState.snow_line,
		GameState.world_seed,
	]
	GameState.water_level = -INF
	GameState.snow_line = INF
	GameState.weather = &"clear"


func after_test() -> void:
	GameState.current_biome = _saved[0]
	GameState.game_minutes = _saved[1]
	GameState.weather = _saved[2]
	GameState.water_level = _saved[3]
	GameState.snow_line = _saved[4]
	GameState.world_seed = _saved[5]


func _needs() -> NeedsComponent:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position.y = 0.2
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var needs := animal.get_node("%NeedsComponent") as NeedsComponent
	needs.set_process(false)
	return needs


func _at(biome: StringName, hour: float) -> void:
	GameState.current_biome = biome
	GameState.game_minutes = hour * 60.0


func test_desert_noons_are_hot_and_its_nights_chilly() -> void:
	var needs := _needs()
	needs.movement = null  # standing still (idle), whether or not it has landed yet
	_at(&"desert", 12.0)
	var desert_noon := needs.felt_warmth()
	_at(&"meadow", 12.0)
	var meadow_noon := needs.felt_warmth()
	assert_float(desert_noon).is_greater(meadow_noon + 1.0)
	_at(&"desert", 0.0)
	var desert_night := needs.felt_warmth()
	_at(&"meadow", 0.0)
	assert_float(desert_night).is_less(needs.felt_warmth() - 1.5)
	# Standing still at midnight in the desert is a little cold; running warms the fox up.
	_at(&"desert", 0.0)
	assert_bool(needs.is_cold()).is_true()
	(
		assert_bool(
			needs.modifiers.is_too_cold(
				desert_night + needs.modifiers.heat(NeedsModel.Activity.RUN)
			)
		)
		. is_false()
	)
	_at(&"savanna", 0.0)  # the savanna's nights are mild
	assert_bool(needs.is_cold()).is_false()
	_at(&"desert", 6.0)  # dawn and dusk are pleasant
	assert_float(absf(needs.felt_warmth())).is_less(1.2)


func test_thirst_drains_faster_in_the_desert_and_savanna() -> void:
	var needs := _needs()
	needs.movement = null  # the same activity (idle) in every biome, landed or not
	var drained := {}
	for biome: StringName in [&"meadow", &"savanna", &"desert"]:
		_at(biome, 10.0)
		needs.set_value(&"thirst", 100.0)
		needs.tick(60.0)
		drained[biome] = 100.0 - needs.value(&"thirst")
	var report := str(drained)
	assert_float(drained[&"desert"]).override_failure_message(report).is_equal_approx(
		drained[&"meadow"] * 1.6, 1e-3
	)
	assert_float(drained[&"savanna"]).override_failure_message(report).is_equal_approx(
		drained[&"meadow"] * 1.2, 1e-3
	)


func test_the_oasis_water_still_cools_and_no_rain_is_felt_in_the_desert() -> void:
	var needs := _needs()
	_at(&"desert", 13.0)
	needs.set_value(&"temperature", 50.0)
	GameState.water_level = needs.get_parent().global_position.y + 0.1  # wading in an oasis
	needs.tick(30.0)
	assert_float(needs.value(&"temperature")).is_greater(50.0)
	GameState.weather = &"rain"
	assert_bool(needs.is_raining()).is_false()
	_at(&"savanna", 13.0)
	assert_bool(needs.is_raining()).is_true()


func test_no_rain_is_shown_over_the_desert() -> void:
	GameState.world_seed = 12345
	var model := WeatherModel.new(12345, WEATHER.transitions())
	var slot := 10
	while model.state_at(slot) != WeatherModel.Kind.RAIN:
		slot += 1
	var weather: Weather = auto_free(Weather.new())
	weather.settings = WEATHER
	weather.terrain = TERRAIN
	add_child(weather)
	weather.set_process(false)
	GameState.current_biome = &"meadow"
	GameState.game_minutes = slot * WEATHER.slot_minutes
	weather.advance(0.0)
	assert_float(weather.rain_here).is_equal(1.0)
	GameState.current_biome = &"desert"  # walking into the desert under the same clouds
	for t in 200:
		weather.advance(0.1)
	assert_float(weather.rain).is_equal(1.0)  # the weather stays global…
	assert_float(weather.shelter).is_equal(1.0)
	assert_float(weather.rain_here).is_equal(0.0)  # …but none falls here
	assert_float(weather.wetness).is_less(1.0)  # and the ground dries


func test_every_other_biome_keeps_its_climate() -> void:
	for biome in TERRAIN.biomes.biomes:
		if biome.id in [&"desert", &"savanna"]:
			continue
		assert_float(biome.night_drop).is_equal(0.0)
		assert_bool(biome.need_multipliers.is_empty()).is_true()
		assert_bool(biome.dry).is_false()
