## Tests for the ambience: which layers play by biome, time of day and rain, cross-fades and
## looping streams on the Ambience bus.
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


func before_test() -> void:
	_saved_biome = GameState.current_biome
	_saved_minutes = GameState.game_minutes


func after_test() -> void:
	GameState.current_biome = _saved_biome
	GameState.game_minutes = _saved_minutes


func _layer(index: int) -> AmbienceLayer:
	return SETTINGS.layers[index]


func test_each_biome_has_its_own_daytime_sound() -> void:
	assert_float(_layer(MEADOW_BIRDS).volume_for(&"meadow", 1.0, 0.0)).is_greater(0.5)
	assert_float(_layer(FOREST_BIRDS).volume_for(&"forest", 1.0, 0.0)).is_greater(0.5)
	assert_float(_layer(RIVER).volume_for(&"river_valley", 1.0, 0.0)).is_greater(0.5)
	assert_float(_layer(WIND).volume_for(&"hills", 1.0, 0.0)).is_greater(0.5)
	assert_float(_layer(FOREST_BIRDS).volume_for(&"hills", 1.0, 0.0)).is_equal(0.0)


func test_crickets_at_night_birds_by_day() -> void:
	for biome: StringName in [&"meadow", &"forest", &"river_valley", &"hills"]:
		assert_float(_layer(CRICKETS).volume_for(biome, 0.0, 0.0)).is_greater(0.3)
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
	GameState.current_biome = &"meadow"
	director.advance(10.0)
	assert_float(director.volume(MEADOW_BIRDS)).is_equal_approx(0.8, 1e-4)
	GameState.current_biome = &"forest"
	director.advance(SETTINGS.fade_seconds * 0.25)
	assert_float(director.volume(MEADOW_BIRDS)).is_between(0.4, 0.7)  # fading out, not cut
	assert_float(director.volume(FOREST_BIRDS)).is_between(0.1, 0.4)  # fading in
	director.advance(SETTINGS.fade_seconds)
	assert_float(director.volume(MEADOW_BIRDS)).is_equal(0.0)
	assert_float(director.volume(FOREST_BIRDS)).is_equal_approx(0.8, 1e-4)


func test_players_loop_on_the_ambience_bus_and_rest_when_silent() -> void:
	var director := _director()
	GameState.current_biome = &"forest"
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
	assert_bool(director.player(FOREST_BIRDS).playing).is_true()
	assert_bool(director.player(MEADOW_BIRDS).playing).is_false()


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
