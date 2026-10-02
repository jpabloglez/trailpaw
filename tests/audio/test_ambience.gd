## Tests for the ambience: which layers play by biome, time of day and rain, cross-fades and
## looping streams on the Ambience bus, and birdsong that comes and goes.
extends GdUnitTestSuite

const SETTINGS: AmbienceSettings = preload("res://data/audio/ambience.tres")
const MEADOW_BIRDS := 0
const FOREST_BIRDS := 1
const RIVER := 2
const WIND := 3
const CRICKETS := 4
const RAIN := 5

var _saved_biome: StringName
var _saved_minutes: float
var _saved_seed: int


func before_test() -> void:
	_saved_biome = GameState.current_biome
	_saved_minutes = GameState.game_minutes
	_saved_seed = GameState.world_seed


func after_test() -> void:
	GameState.current_biome = _saved_biome
	GameState.game_minutes = _saved_minutes
	GameState.world_seed = _saved_seed


func _layer(index: int) -> AmbienceLayer:
	return SETTINGS.layers[index]


func test_each_biome_has_its_own_daytime_sound() -> void:
	assert_float(_layer(MEADOW_BIRDS).volume_for(&"meadow", 1.0, 0.0)).is_between(0.2, 0.4)
	assert_float(_layer(FOREST_BIRDS).volume_for(&"forest", 1.0, 0.0)).is_between(0.2, 0.4)
	assert_float(_layer(RIVER).volume_for(&"river_valley", 1.0, 0.0)).is_greater(0.4)
	assert_float(_layer(WIND).volume_for(&"hills", 1.0, 0.0)).is_greater(0.4)
	assert_float(_layer(FOREST_BIRDS).volume_for(&"hills", 1.0, 0.0)).is_equal(0.0)


func test_crickets_at_night_birds_by_day() -> void:
	for biome: StringName in [&"meadow", &"forest", &"river_valley", &"hills"]:
		assert_float(_layer(CRICKETS).volume_for(biome, 0.0, 0.0)).is_greater(0.2)
		assert_float(_layer(CRICKETS).volume_for(biome, 1.0, 0.0)).is_equal(0.0)
	assert_float(_layer(MEADOW_BIRDS).volume_for(&"meadow", 0.0, 0.0)).is_equal(0.0)


func test_rain_drowns_the_birds_and_is_heard_everywhere() -> void:
	var dry := _layer(MEADOW_BIRDS).volume_for(&"meadow", 1.0, 0.0)
	assert_float(_layer(MEADOW_BIRDS).volume_for(&"meadow", 1.0, 1.0)).is_less(dry * 0.5)
	assert_float(_layer(RAIN).volume_for(&"hills", 1.0, 0.0)).is_equal(0.0)
	assert_float(_layer(RAIN).volume_for(&"hills", 1.0, 1.0)).is_greater(0.5)


func _director() -> AmbienceDirector:
	var director: AmbienceDirector = auto_free(AmbienceDirector.new())
	director.settings = SETTINGS
	add_child(director)
	director.set_process(false)
	return director


func test_cross_fades_when_the_biome_changes() -> void:
	var director := _director()
	GameState.current_biome = &"river_valley"
	director.advance(10.0)
	var river := _layer(RIVER).volume_for(&"river_valley", 1.0, 0.0)
	assert_float(director.volume(RIVER)).is_equal_approx(river, 1e-4)
	GameState.current_biome = &"meadow"
	director.advance(SETTINGS.fade_seconds * 0.25)
	assert_float(director.volume(RIVER)).is_between(0.1, river - 0.1)  # fading out, not cut
	director.advance(SETTINGS.fade_seconds)
	assert_float(director.volume(RIVER)).is_equal(0.0)
	var wind := _layer(WIND).volume_for(&"meadow", 1.0, 0.0)
	assert_float(director.volume(WIND)).is_equal_approx(wind, 1e-4)


func test_players_loop_on_the_ambience_bus_and_rest_when_silent() -> void:
	var director := _director()
	GameState.current_biome = &"river_valley"
	director.advance(10.0)
	for i in SETTINGS.layers.size():
		var player := director.player(i)
		assert_str(String(player.bus)).is_equal("Ambience")
		var stream := player.stream
		var loops: bool = (
			stream.loop
			if not stream is AudioStreamWAV
			else (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
		)
		assert_bool(loops).override_failure_message(str(i)).is_true()
	assert_bool(director.player(RIVER).playing).is_true()
	assert_bool(director.player(FOREST_BIRDS).playing).is_false()


# Seconds (in 0.5 s steps over 10 minutes) each layer is audible, and how many spells began.
func _listen(director: AmbienceDirector, index: int) -> Vector2i:
	var heard := 0
	var spells := 0
	var was_open := director.is_open(index)
	for _step in 1200:
		director.advance(0.5)
		if director.volume(index) > 0.05:
			heard += 1
		if director.is_open(index) and not was_open:
			spells += 1
		was_open = director.is_open(index)
	return Vector2i(heard / 2, spells)


func test_birdsong_comes_and_goes() -> void:
	GameState.world_seed = 12345
	GameState.current_biome = &"meadow"
	var director := _director()
	var meadow := _listen(director, MEADOW_BIRDS)
	assert_int(meadow.y).is_greater_equal(5)  # several spells in 10 minutes…
	assert_int(meadow.x).is_between(60, 300)  # …but silent most of the time
	var wind := _listen(director, WIND)
	assert_int(wind.x).is_equal(600)  # the bed under it is continuous
	GameState.current_biome = &"forest"
	var forest := _listen(director, FOREST_BIRDS)
	assert_int(forest.x).is_between(120, 420)  # the forest is livelier than the meadow


func test_spells_follow_the_world_seed() -> void:
	GameState.current_biome = &"meadow"
	GameState.world_seed = 777
	var first := _listen(_director(), MEADOW_BIRDS)
	var again := _listen(_director(), MEADOW_BIRDS)
	GameState.world_seed = 778
	var other := _listen(_director(), MEADOW_BIRDS)
	assert_that(again).is_equal(first)
	assert_that(other).is_not_equal(first)


func test_daylight_follows_the_sky() -> void:
	var director := _director()
	var cycle: DayNightCycle = auto_free(DayNightCycle.new())
	cycle.settings = load("res://data/world/day_night.tres")
	director.day_night = cycle
	GameState.game_minutes = 12 * 60.0
	assert_float(director.daylight()).is_equal(1.0)
	GameState.game_minutes = 1 * 60.0
	assert_float(director.daylight()).is_equal(0.0)


func test_the_ambience_loops_are_small_and_credited() -> void:
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for layer in SETTINGS.layers:
		var path := layer.stream.resource_path
		assert_str(credits).contains(path.trim_prefix("res://"))
		var bytes := FileAccess.get_file_as_bytes(path).size()
		assert_int(bytes).override_failure_message(path).is_less(2_500_000)
