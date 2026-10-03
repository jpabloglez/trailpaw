## Tests for the perf probe ([PerfProbe]): a short flight over the real world writes a CSV that
## tools/perf_report.py can read — the JSON header, every column, real (varying) frame times.
extends GdUnitTestSuite

const SCENE: String = "res://scenes/debug/perf_probe.tscn"
const OUT: String = "user://test_perf/probe.csv"
const MAX_FRAMES: int = 3000

var _saved_quality: QualityPreset
var _saved_vsync: bool
var _saved_dir: String


func before_test() -> void:
	_saved_quality = Settings.quality
	_saved_vsync = Settings.vsync
	_saved_dir = SaveSystem.save_dir
	DirAccess.remove_absolute(OUT)


func after_test() -> void:
	Settings.set_quality(_saved_quality)
	Settings.set_vsync(_saved_vsync)
	SaveSystem.save_dir = _saved_dir
	GameState.clock_scale = 1.0
	FloatingOrigin.reset()
	DirAccess.remove_absolute(OUT)


func test_a_short_flight_writes_a_readable_csv() -> void:
	var probe: PerfProbe = auto_free(load(SCENE).instantiate())
	probe.distance = 60.0
	probe.speed = 20.0
	probe.out_path = OUT
	probe.quit_when_done = false
	var written: Array[String] = []
	probe.finished.connect(func(path: String) -> void: written.append(path))
	add_child(probe)
	assert_float(GameState.clock_scale).is_equal(0.0)  # noon, frozen
	assert_bool(Settings.vsync).is_false()  # measures headroom, not the refresh rate
	for i in MAX_FRAMES:
		await get_tree().process_frame
		if not written.is_empty():
			break
	assert_array(written).contains_exactly([OUT])
	var lines := FileAccess.get_file_as_string(OUT).split("\n", false)
	assert_str(lines[0]).starts_with("# ")
	var header: Dictionary = JSON.parse_string(lines[0].substr(2))
	for key: String in ["gpu", "renderer", "preset", "seed", "resolution", "godot", "vsync"]:
		assert_bool(header.has(key)).override_failure_message(key).is_true()
	assert_str(str(header["preset"])).is_equal("medium")
	assert_str(lines[1]).is_equal(",".join(PerfProbe.COLUMNS))
	assert_int(lines.size() - 2).is_equal(probe.frame_count()).is_greater(10)
	var times := {}
	for row in lines.slice(2):
		var cells := row.split(",")
		assert_int(cells.size()).is_equal(PerfProbe.COLUMNS.size())
		assert_str(cells[cells.size() - 1]).is_not_empty()  # the biome
		times[cells[2]] = true
	assert_int(times.size()).is_greater(1)  # real frame times, not a constant delta
