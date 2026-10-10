## Tests for the hamlets' sounds (Phase 16): hens about the yard by day only, the rooster once at
## dawn, calls from the pen by day, claps when a villager shoos the fox; and every sound credited.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: HamletSoundSettings = preload("res://data/audio/hamlet_sounds.tres")

var _saved_seed: int
var _saved_minutes: float


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_minutes = GameState.game_minutes
	GameState.world_seed = 12345
	GameState.game_minutes = 12.0 * 60.0


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.game_minutes = _saved_minutes


func _hamlet() -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var director: HamletDirector = auto_free(HamletDirector.new())
	director.terrain = TERRAIN
	director.player = player
	add_child(director)
	director.set_process(false)
	var hamlet: HamletLayout = director.hamlets_near(Vector3.ZERO, 2000.0)[0]
	player.global_position = GameState.local_position(hamlet.centre + Vector3(0, 0, 40))
	var sounds: HamletSounds = auto_free(HamletSounds.new())
	sounds.settings = SETTINGS
	sounds.director = director
	add_child(sounds)
	sounds.set_process(false)
	director.refresh()
	return [sounds, hamlet]


func test_the_clock_crossing_a_mark() -> void:
	assert_bool(HamletSounds.crosses(5.9, 6.1, 6.0)).is_true()
	assert_bool(HamletSounds.crosses(6.1, 6.2, 6.0)).is_false()
	assert_bool(HamletSounds.crosses(23.9, 0.1, 0.0)).is_true()  # past midnight
	assert_bool(HamletSounds.crosses(23.9, 0.1, 6.0)).is_false()
	assert_bool(HamletSounds.crosses(1.0, 20.0, 6.0)).is_false()  # a long jump (rest, load)


func test_hens_are_heard_by_day_only() -> void:
	var made := _hamlet()
	var sounds: HamletSounds = made[0]
	var yard := sounds.yard_of((made[1] as HamletLayout).cell)
	assert_object(yard).is_not_null()
	assert_float(yard.max_distance).is_equal(SETTINGS.yard_reach.y)
	sounds.update(0.25)
	assert_bool(yard.playing).is_true()
	GameState.game_minutes = 23.0 * 60.0
	sounds.update(0.25)
	assert_bool(yard.playing).is_false()


func test_the_rooster_crows_once_at_dawn_and_the_pen_calls_by_day() -> void:
	var sounds: HamletSounds = _hamlet()[0]
	GameState.game_minutes = 5.9 * 60.0
	sounds.update(0.25)
	assert_int(sounds.crows).is_equal(0)
	GameState.game_minutes = 6.05 * 60.0
	sounds.update(0.25)
	assert_int(sounds.crows).is_equal(1)
	GameState.game_minutes = 6.3 * 60.0
	sounds.update(0.25)
	assert_int(sounds.crows).is_equal(1)  # once a day
	for t in 120:  # two minutes of a day: the animals call now and then
		sounds.update(1.0)
	assert_int(sounds.calls).is_greater(1)
	var calls := sounds.calls
	GameState.game_minutes = 23.0 * 60.0
	for t in 120:
		sounds.update(1.0)
	assert_int(sounds.calls).is_equal(calls)  # quiet at night


func test_a_shoo_claps_where_the_villager_is() -> void:
	var sounds: HamletSounds = _hamlet()[0]
	EventBus.fox_shooed.emit(Vector3(5, 0, 7))
	var clap := sounds.shoo_player()
	assert_bool(clap.playing).is_true()
	assert_vector(clap.global_position).is_equal_approx(Vector3(5, 1.2, 7), Vector3.ONE * 1e-3)


func test_every_sound_is_credited_and_small() -> void:
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for stream: AudioStream in (
		[SETTINGS.yard, SETTINGS.rooster, SETTINGS.shoo] + SETTINGS.pen_calls
	):
		var path := stream.resource_path
		assert_str(credits).contains(path.trim_prefix("res://"))
		(
			assert_int(FileAccess.get_file_as_bytes(path).size())
			. override_failure_message(path)
			. is_less(1_000_000)
		)
