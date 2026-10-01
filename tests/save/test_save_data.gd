## Tests for saved games: SaveData round-trips, migrations from the v1 fixture, the atomic
## JSON SaveSystem and its error handling.
extends GdUnitTestSuite

const FIXTURE_V1: String = "res://tests/fixtures/save_v1.json"
const TEST_DIR: String = "user://test_saves"

var _saved_dir: String


func before_test() -> void:
	_saved_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.erase()


func after_test() -> void:
	SaveSystem.erase()
	SaveSystem.save_dir = _saved_dir


func _sample() -> SaveData:
	var save := SaveData.new()
	save.world_seed = 987654
	save.player_position = Vector3(12345.678, 9.25, -4321.5)
	save.player_yaw = 1.25
	save.needs = {&"hunger": 55.5, &"thirst": 31.0, &"temperature": 90.0, &"energy": 12.75}
	save.game_minutes = 1440.0 * 3 + 615.5
	var store := ChunkDeltaStore.new()
	store.deplete(Vector2i(192, -67), &"berries", 4, 5000.0)
	save.chunk_deltas = store.to_dict()
	save.biome = &"forest"
	save.species = "res://data/species/fox.tres"
	return save


func _assert_same(a: SaveData, b: SaveData) -> void:
	assert_int(b.world_seed).is_equal(a.world_seed)
	assert_vector(b.player_position).is_equal_approx(a.player_position, Vector3.ONE * 1e-4)
	assert_float(b.player_yaw).is_equal_approx(a.player_yaw, 1e-6)
	assert_dict(b.needs).is_equal(a.needs)
	assert_float(b.game_minutes).is_equal_approx(a.game_minutes, 1e-6)
	assert_str(String(b.biome)).is_equal(String(a.biome))
	assert_str(b.species).is_equal(a.species)
	var restored := ChunkDeltaStore.new()
	restored.from_dict(b.chunk_deltas)
	assert_bool(restored.is_depleted(Vector2i(192, -67), &"berries", 4, 4000.0)).is_true()


# --- data and migrations ------------------------------------------------------------------


func test_round_trip_through_json_keeps_everything() -> void:
	var save := _sample()
	var text := JSON.stringify(save.to_dict())
	var back := SaveData.from_dict(SaveMigrations.migrate(JSON.parse_string(text)))
	_assert_same(save, back)


func test_migrates_the_v1_fixture() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_V1))
	assert_int(int(data["version"])).is_equal(1)
	var save := SaveData.from_dict(SaveMigrations.migrate(data))
	assert_int(save.world_seed).is_equal(424242)
	assert_vector(save.player_position).is_equal(Vector3(1530.25, 7.5, -812.0))
	assert_float(save.needs[&"hunger"]).is_equal(61.5)
	assert_float(save.needs[&"energy"]).is_equal(73.25)
	assert_float(save.game_minutes).is_equal(480.0)  # added by v1 → v2: 08:00, first day
	assert_str(save.species).is_equal("res://data/species/fox.tres")
	assert_bool(ResourceLoader.exists(save.species)).is_true()


func test_migration_does_not_touch_its_input() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_V1))
	SaveMigrations.migrate(data)
	assert_int(int(data["version"])).is_equal(1)
	assert_bool(data.has("seed")).is_true()


func test_unknown_and_future_versions_are_rejected() -> void:
	var reasons: Array[String] = []
	assert_dict(SaveMigrations.migrate({"world_seed": 1}, reasons)).is_empty()
	assert_dict(SaveMigrations.migrate({"version": SaveData.VERSION + 1}, reasons)).is_empty()
	assert_dict(SaveMigrations.migrate({"version": 0}, reasons)).is_empty()
	assert_int(reasons.size()).is_equal(3)


# --- the save file ------------------------------------------------------------------------


func test_write_then_read_restores_the_game() -> void:
	var save := _sample()
	assert_int(SaveSystem.write(save)).is_equal(OK)
	assert_bool(SaveSystem.exists()).is_true()
	var back := SaveSystem.read()
	assert_object(back).is_not_null()
	_assert_same(save, back)
	assert_int(back.saved_at).is_greater(0)


func test_writes_are_atomic_and_replace_the_previous_save() -> void:
	var first := _sample()
	SaveSystem.write(first)
	var second := _sample()
	second.game_minutes = 99.0
	assert_int(SaveSystem.write(second)).is_equal(OK)
	assert_bool(FileAccess.file_exists(SaveSystem.path() + SaveSystem.TEMP_SUFFIX)).is_false()
	assert_float(SaveSystem.read().game_minutes).is_equal(99.0)


func test_a_save_left_between_write_and_replace_is_recovered() -> void:
	SaveSystem.write(_sample())
	DirAccess.rename_absolute(SaveSystem.path(), SaveSystem.path() + SaveSystem.TEMP_SUFFIX)
	assert_object(SaveSystem.read()).is_not_null()


func test_a_corrupt_or_missing_save_is_reported_not_loaded() -> void:
	assert_object(SaveSystem.read()).is_null()
	assert_str(SaveSystem.last_error).is_equal("no save")
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open(SaveSystem.path(), FileAccess.WRITE)
	file.store_string('{"version": 2, "world_seed": ')
	file.close()
	assert_object(SaveSystem.read()).is_null()
	assert_str(SaveSystem.last_error).starts_with("corrupt save")
	file = FileAccess.open(SaveSystem.path(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 99}))
	file.close()
	assert_object(SaveSystem.read()).is_null()
	assert_str(SaveSystem.last_error).contains("newer")


func test_erase_removes_the_save() -> void:
	SaveSystem.write(_sample())
	SaveSystem.erase()
	assert_bool(SaveSystem.exists()).is_false()


func test_saving_is_signalled() -> void:
	var paths: Array[String] = []
	var on_saved := func(p: String) -> void: paths.append(p)
	SaveSystem.saved.connect(on_saved)
	SaveSystem.write(_sample())
	SaveSystem.saved.disconnect(on_saved)
	assert_array(paths).contains_exactly([SaveSystem.path()])
