## Tests for the music (Phase 20): the themes and moments of the data, and the director's spells
## (silence, a whole theme, silence), fades on a change of biome or moment, a settled biome
## before a change counts, silence in the rain and while resting, the frequency setting, the
## title screen, and the menu option.
extends GdUnitTestSuite

const MUSIC: MusicSettings = preload("res://data/audio/music.tres")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const TEST_PATH: String = "user://test_music_settings.cfg"
const LENGTH: float = 30.0  # seconds of each stand-in theme

var _saved: Array = []
var _day: AudioStream
var _night: AudioStream


func before() -> void:
	_day = _tone(LENGTH)
	_night = _tone(LENGTH)


func before_test() -> void:
	_saved = [
		GameState.current_biome,
		GameState.game_minutes,
		GameState.clock_scale,
		GameState.world_seed,
		Settings.music_frequency,
		Settings.config_path,
	]
	GameState.current_biome = &"meadow"
	GameState.game_minutes = 12.0 * 60.0
	GameState.clock_scale = 1.0
	GameState.world_seed = 12345
	Settings.music_frequency = &"sometimes"


func after_test() -> void:
	GameState.current_biome = _saved[0]
	GameState.game_minutes = _saved[1]
	GameState.clock_scale = _saved[2]
	GameState.world_seed = _saved[3]
	Settings.music_frequency = _saved[4]
	Settings.config_path = _saved[5]
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


# A quiet stand-in theme of [param seconds].
static func _tone(seconds: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(SynthSounds.RATE * seconds))
	for i in samples.size():
		samples[i] = sin(TAU * 220.0 * i / SynthSounds.RATE) * 0.01
	return SynthSounds.to_wav(samples)


# The real timings with short stand-in meadow themes (day and night).
func _settings() -> MusicSettings:
	var made: MusicSettings = MUSIC.duplicate()
	var meadow := MusicTheme.new()
	meadow.biome = &"meadow"
	meadow.day = _day
	meadow.night = _night
	made.themes = [meadow] as Array[MusicTheme]
	return made


func _director(weather: Weather = null) -> MusicDirector:
	var director: MusicDirector = auto_free(MusicDirector.new())
	director.settings = _settings()
	director.weather = weather
	add_child(director)
	director.set_process(false)
	return director


func _run(director: MusicDirector, seconds: float, step: float = 0.25) -> void:
	for i in int(seconds / step):
		director.advance(step)


# Runs until it plays (true) or [param limit] seconds pass.
func _until_playing(director: MusicDirector, limit: float) -> bool:
	for i in int(limit / 0.25):
		director.advance(0.25)
		if director.phase() == MusicDirector.Phase.PLAYING:
			return true
	return false


func test_the_data_is_valid_and_the_meadow_has_all_four_moments() -> void:
	assert_array(Array(MUSIC.get_validation_errors())).is_empty()
	var meadow := MUSIC.theme_for(&"meadow")
	assert_object(meadow).is_not_null()
	for moment: StringName in [&"day", &"dawn", &"dusk", &"night"]:
		assert_object(meadow.stream_for(moment)).is_not_null()
		assert_float(meadow.stream_for(moment).get_length()).is_between(120.0, 300.0)
	assert_object(meadow.stream_for(&"dawn")).is_not_equal(meadow.day)
	var biomes: Array[StringName] = []
	for biome in TERRAIN.biomes.biomes:
		biomes.append(biome.id)
	for theme in MUSIC.themes:
		assert_bool(biomes.has(theme.biome)).is_true()
	var lone := MusicTheme.new()
	lone.day = _day
	assert_object(lone.stream_for(&"night")).is_equal(_day)  # a missing moment plays the day's


func test_the_moments_follow_the_hours() -> void:
	assert_str(String(MUSIC.moment_of(4.9))).is_equal("night")
	assert_str(String(MUSIC.moment_of(5.0))).is_equal("dawn")
	assert_str(String(MUSIC.moment_of(8.0))).is_equal("day")
	assert_str(String(MUSIC.moment_of(17.9))).is_equal("day")
	assert_str(String(MUSIC.moment_of(18.0))).is_equal("dusk")
	assert_str(String(MUSIC.moment_of(21.0))).is_equal("night")
	assert_str(String(MUSIC.moment_of(23.9))).is_equal("night")


func test_silence_first_then_a_whole_theme_then_silence_again() -> void:
	var director := _director()
	director.advance(0.0)
	var first := director.waiting()
	assert_float(first).is_between(MUSIC.first_spell.x, MUSIC.first_spell.y)
	_run(director, first - 1.0)
	assert_int(director.phase()).is_equal(MusicDirector.Phase.WAITING)
	assert_bool(_until_playing(director, 2.0)).is_true()
	assert_object(director.current()).is_equal(_day)
	assert_str(String(director.player().bus)).is_equal("Music")
	_run(director, MUSIC.fade_in + 0.5)
	assert_float(director.volume()).is_equal(1.0)  # faded in
	_run(director, LENGTH)
	assert_int(director.phase()).is_equal(MusicDirector.Phase.WAITING)  # the whole theme ended
	assert_object(director.current()).is_null()
	assert_float(director.waiting()).is_between(MUSIC.pauses.x - 1.0, MUSIC.pauses.y)
	assert_bool(_until_playing(director, MUSIC.pauses.y + 1.0)).is_true()  # and again


func test_nightfall_fades_the_day_theme_and_brings_the_night_one() -> void:
	var director := _director()
	assert_bool(_until_playing(director, MUSIC.first_spell.y + 1.0)).is_true()
	GameState.game_minutes = 22.0 * 60.0
	director.advance(0.25)
	assert_int(director.phase()).is_equal(MusicDirector.Phase.FADING)
	_run(director, MUSIC.fade_out)
	assert_int(director.phase()).is_equal(MusicDirector.Phase.WAITING)
	assert_float(director.waiting()).is_less_equal(MUSIC.change_gap.y)
	assert_bool(_until_playing(director, MUSIC.change_gap.y + 1.0)).is_true()
	assert_object(director.current()).is_equal(_night)


func test_a_biome_without_music_fades_it_once_settled_and_borders_do_not_flicker() -> void:
	var director := _director()
	assert_bool(_until_playing(director, MUSIC.first_spell.y + 1.0)).is_true()
	for flick in 4:  # back and forth along a border, never settling
		GameState.current_biome = &"forest" if flick % 2 == 0 else &"meadow"
		_run(director, MUSIC.settle_seconds * 0.5)
		assert_int(director.phase()).is_equal(MusicDirector.Phase.PLAYING)
	GameState.current_biome = &"forest"
	_run(director, MUSIC.settle_seconds + 0.5)
	assert_int(director.phase()).is_equal(MusicDirector.Phase.FADING)
	_run(director, MUSIC.fade_out + MUSIC.change_gap.y + 30.0)
	assert_object(director.current()).is_null()  # no forest theme: silence


func test_rain_and_rest_silence_the_music_until_they_end() -> void:
	var weather: Weather = auto_free(Weather.new())
	var director := _director(weather)
	assert_bool(_until_playing(director, MUSIC.first_spell.y + 1.0)).is_true()
	weather.rain_here = 0.8
	_run(director, MUSIC.fade_out + 0.5)
	assert_int(director.phase()).is_equal(MusicDirector.Phase.WAITING)
	_run(director, 30.0)
	assert_object(director.current()).is_null()  # still raining
	weather.rain_here = 0.0
	assert_bool(_until_playing(director, MUSIC.change_gap.y + 2.0)).is_true()
	GameState.clock_scale = GameState.CLOCK.rest_scale  # resting
	_run(director, MUSIC.fade_out + 0.5)
	assert_object(director.current()).is_null()


func test_never_stops_the_music_and_often_shortens_the_silences() -> void:
	var director := _director()
	assert_bool(_until_playing(director, MUSIC.first_spell.y + 1.0)).is_true()
	Settings.set_music_frequency(&"never")
	_run(director, MUSIC.fade_out + MUSIC.change_gap.y + 60.0)
	assert_object(director.current()).is_null()
	Settings.set_music_frequency(&"often")
	assert_bool(_until_playing(director, 3.0)).is_true()
	_run(director, LENGTH + MUSIC.fade_in)
	assert_float(director.waiting()).is_less_equal(MUSIC.pauses.y * MUSIC.often_factor)


func test_the_frequency_is_saved_and_bad_values_ignored() -> void:
	Settings.config_path = TEST_PATH
	Settings.set_music_frequency(&"often")
	Settings.set_music_frequency(&"loud")  # not a frequency: ignored
	assert_str(String(Settings.music_frequency)).is_equal("often")
	assert_int(Settings.save_settings()).is_equal(OK)
	Settings.music_frequency = &"sometimes"
	Settings.load_settings()
	assert_str(String(Settings.music_frequency)).is_equal("often")


func test_the_title_screen_plays_at_once_and_comes_back_soon() -> void:
	var director := _director()
	director.title_mode = true
	GameState.current_biome = &"desert"  # whatever is behind the menu
	GameState.game_minutes = 23.0 * 60.0
	director.advance(0.25)
	assert_int(director.phase()).is_equal(MusicDirector.Phase.PLAYING)
	assert_object(director.current()).is_equal(_day)  # the title theme: the meadow by day
	_run(director, LENGTH)
	assert_float(director.waiting()).is_equal_approx(MUSIC.title_pause, 0.5)


func test_the_menu_sets_how_often_music_plays() -> void:
	var menu: SettingsMenu = auto_free(SettingsMenu.new())
	add_child(menu)
	menu.open()
	var option := menu.control("MusicFrequency") as OptionButton
	assert_object(option).is_not_null()
	assert_int(option.selected).is_equal(1)  # sometimes
	option.item_selected.emit(2)
	assert_str(String(Settings.music_frequency)).is_equal("never")
	menu.close()


func test_the_world_hosts_the_director_with_the_music_data() -> void:
	var world: Node = auto_free(load("res://scenes/main/world.tscn").instantiate())
	var director := world.get_node_or_null("MusicDirector") as MusicDirector
	assert_object(director).is_not_null()
	assert_object(director.settings).is_equal(MUSIC)
	assert_object(director.weather).is_not_null()
	assert_object((world as WorldController).music).is_equal(director)
