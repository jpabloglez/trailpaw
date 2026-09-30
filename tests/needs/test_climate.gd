## Tests for climate effects on needs: the time of day and the weather change the felt warmth,
## and rain makes the animal less thirsty.
extends GdUnitTestSuite

const MODIFIERS: NeedModifiers = preload("res://data/needs/need_modifiers.tres")
const IDS: Array[StringName] = [&"hunger", &"thirst", &"temperature", &"energy"]
const TROT := NeedsModel.Activity.TROT

var _saved_minutes: float
var _saved_weather: StringName
var _saved_biome: StringName


func before_test() -> void:
	_saved_minutes = GameState.game_minutes
	_saved_weather = GameState.weather
	_saved_biome = GameState.current_biome


func after_test() -> void:
	GameState.game_minutes = _saved_minutes
	GameState.weather = _saved_weather
	GameState.current_biome = _saved_biome


func _model() -> NeedsModel:
	var definitions: Array[NeedDefinition] = []
	for id in IDS:
		definitions.append(load("res://data/needs/%s.tres" % id))
	return NeedsModel.new(definitions, MODIFIERS)


func test_nights_are_cool_and_noons_warm() -> void:
	assert_float(MODIFIERS.time_warmth(0.0)).is_equal_approx(MODIFIERS.night_warmth, 1e-5)
	assert_float(MODIFIERS.time_warmth(12.0)).is_equal_approx(MODIFIERS.noon_warmth, 1e-5)
	assert_float(MODIFIERS.night_warmth).is_less(0.0)
	assert_float(MODIFIERS.noon_warmth).is_greater(0.0)
	assert_float(MODIFIERS.time_warmth(23.99)).is_equal_approx(MODIFIERS.time_warmth(0.01), 1e-3)


func test_clouds_and_rain_cool_down() -> void:
	assert_float(MODIFIERS.weather_warmth_for(&"clear")).is_equal(0.0)
	assert_float(MODIFIERS.weather_warmth_for(&"cloudy")).is_less(0.0)
	assert_float(MODIFIERS.weather_warmth_for(&"rain")).is_less(
		MODIFIERS.weather_warmth_for(&"cloudy")
	)


func test_rain_means_less_thirst_but_the_same_hunger() -> void:
	var model := _model()
	var dry := model.rate_for(&"thirst", TROT, 0.0, false, false)
	var wet := model.rate_for(&"thirst", TROT, 0.0, false, true)
	assert_float(wet / dry).is_equal_approx(0.7, 1e-4)
	assert_float(model.rate_for(&"hunger", TROT, 0.0, false, true)).is_equal(
		model.rate_for(&"hunger", TROT, 0.0, false, false)
	)


func test_the_animal_feels_the_hour_and_the_weather() -> void:
	var animal: Animal = auto_free(load("res://scenes/player/animal.tscn").instantiate())
	add_child(animal)
	var needs := animal.get_node("%NeedsComponent") as NeedsComponent
	GameState.current_biome = &"meadow"
	GameState.weather = &"clear"
	GameState.game_minutes = 12 * 60.0
	var noon := needs.felt_warmth()
	GameState.game_minutes = 0.0
	var midnight := needs.felt_warmth()
	assert_float(noon - midnight).is_equal_approx(
		MODIFIERS.noon_warmth - MODIFIERS.night_warmth, 1e-4
	)
	GameState.weather = &"rain"
	assert_float(needs.felt_warmth()).is_less(midnight)
	assert_bool(needs.is_raining()).is_true()
	# In the warm hills a rainy night cools the fox down instead of heating it up.
	GameState.current_biome = &"hills"
	var comfort_rate := needs.model.rate_for(&"temperature", TROT, needs.felt_warmth())
	GameState.weather = &"clear"
	GameState.game_minutes = 12 * 60.0
	assert_float(comfort_rate).is_greater(
		needs.model.rate_for(&"temperature", TROT, needs.felt_warmth())
	)
	assert_str(needs.get_debug_lines()[0]).contains("feels")
