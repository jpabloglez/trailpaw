class_name PerfProbe
extends Node
## Performance probe on the real game ([code]world.tscn[/code]): a camera flies a fixed path
## through all four biomes at noon (clock frozen, so the light and the weather are the same on
## every run) and the real frame time of every frame is recorded with what the game was doing,
## then written as CSV for [code]python -m tools.perf_report[/code]. V-Sync is turned off while
## it measures (not saved), so frame times show the real headroom instead of the refresh rate.
##
## Run (the window shows the world while it measures):
## [code]godot --path . res://scenes/debug/perf_probe.tscn -- [--distance=3600] [--speed=15]
## [--preset=medium] [--out=user://perf/run.csv][/code]
## [br][br]
## The CSV starts with one [code]# {json}[/code] line (GPU, driver, renderer, resolution,
## preset, seed, Godot version), then a header row and one row per frame. Rows are kept in
## packed arrays and written once at the end, so measuring adds no disk I/O.

## The probe finished and wrote [param path].
signal finished(path: String)

## Columns of the CSV, in order.
const COLUMNS: PackedStringArray = [
	"frame",
	"t_s",
	"frame_ms",
	"render_cpu_ms",
	"render_gpu_ms",
	"draw_calls",
	"primitives",
	"chunks_built",
	"build_ms",
	"fauna",
	"biome",
]
## World seed of every run (comparable paths).
const SEED: int = 12345
## Noon: the clock is frozen there.
const NOON_MINUTES: float = 12.0 * 60.0
## Height of the camera above the terrain (m): roughly where the player camera is.
const ALTITUDE: float = 4.0

## The playable world.
@export var world_scene: PackedScene
## Metres to fly along +X (the spawn meadow outwards crosses every biome within ≈ 3.2 km).
@export var distance: float = 3600.0
## Flight speed (m/s).
@export var speed: float = 15.0
## Quality preset id ([code]low[/code], [code]medium[/code], [code]high[/code]).
@export var preset: StringName = &"medium"
## Output file (empty: [code]user://perf/<date>_<preset>.csv[/code]).
@export var out_path: String = ""
## Quit the game when done (off in tests).
@export var quit_when_done: bool = true

var _world: WorldController
var _camera: AttractCamera
var _fauna: FaunaDirector
var _started: bool = false
var _start_x: float = 0.0
var _start_us: int = 0
var _last_us: int = 0
var _biomes: Array[StringName] = []
var _frame_ms := PackedFloat32Array()
var _t_s := PackedFloat32Array()
var _render_cpu_ms := PackedFloat32Array()
var _render_gpu_ms := PackedFloat32Array()
var _draw_calls := PackedInt32Array()
var _primitives := PackedInt32Array()
var _chunks_built := PackedInt32Array()
var _build_ms := PackedFloat32Array()
var _fauna_count := PackedInt32Array()
var _biome_index := PackedInt32Array()


func _ready() -> void:
	distance = _arg_float("--distance=", distance)
	speed = _arg_float("--speed=", speed)
	preset = StringName(_arg("--preset=", String(preset)))
	out_path = _arg("--out=", out_path)
	if Settings.QUALITY_PATHS.has(preset):
		Settings.set_quality(load(Settings.QUALITY_PATHS[preset]))
	Settings.set_vsync(false)  # applied, not saved
	SaveSystem.save_dir = "user://perf/saves"  # attract mode never saves; belt and braces
	_world = world_scene.instantiate() as WorldController
	_world.attract_mode = true
	_world.world_seed = SEED
	add_child(_world)
	GameState.game_minutes = NOON_MINUTES
	GameState.clock_scale = 0.0
	_camera = _world.attract_camera()
	_camera.speed = 0.0  # still until the first area has loaded
	_camera.altitude = ALTITUDE
	_fauna = _world.get_node_or_null("FaunaDirector") as FaunaDirector
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("[perf] %.0f m at %.1f m/s, preset %s, seed %d" % [distance, speed, preset, SEED])


func _exit_tree() -> void:
	GameState.clock_scale = 1.0


func _process(_delta: float) -> void:
	if _world == null:
		return
	var now := Time.get_ticks_usec()
	if not _started:
		if _world.streamer.is_idle() and _world.streamer.is_ready_at(_camera.global_position):
			_started = true
			_camera.speed = speed
			_start_x = GameState.absolute_position(_camera.global_position).x
			_start_us = now
			_last_us = now
		return
	_record(now)
	_last_us = now
	if GameState.absolute_position(_camera.global_position).x - _start_x >= distance:
		_finish()


## Frames measured so far.
func frame_count() -> int:
	return _frame_ms.size()


## Whether the flight has started (the first area finished loading).
func is_measuring() -> bool:
	return _started


func _record(now: int) -> void:
	_frame_ms.append((now - _last_us) / 1000.0)
	_t_s.append((now - _start_us) / 1_000_000.0)
	# Per-frame render times (the Performance TIME_* monitors only refresh about once a second).
	var viewport := get_viewport().get_viewport_rid()
	_render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
	_render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var stats := _world.streamer.stats()
	var built: int = stats["last_frame_built"]
	_chunks_built.append(built)
	_build_ms.append(stats["last_build_ms"] if built > 0 else 0.0)
	_fauna_count.append(_fauna.agents().size() if _fauna != null else 0)
	var biome := GameState.current_biome
	var index := _biomes.find(biome)
	if index < 0:
		_biomes.append(biome)
		index = _biomes.size() - 1
	_biome_index.append(index)


func _finish() -> void:
	set_process(false)
	_camera.speed = 0.0
	var path := out_path if out_path != "" else _default_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("PerfProbe: cannot write %s" % path)
	else:
		file.store_line("# " + JSON.stringify(_header()))
		file.store_line(",".join(COLUMNS))
		for i in _frame_ms.size():
			file.store_line(_row(i))
		file.close()
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var p95 := (
		sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))] if not sorted.is_empty() else 0.0
	)
	print(
		(
			"[perf] %d frames, p95 %.2f ms → %s"
			% [_frame_ms.size(), p95, ProjectSettings.globalize_path(path)]
		)
	)
	finished.emit(path)
	if quit_when_done:
		get_tree().quit()


func _row(i: int) -> String:
	return (
		"%d,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%.3f,%d,%s"
		% [
			i,
			_t_s[i],
			_frame_ms[i],
			_render_cpu_ms[i],
			_render_gpu_ms[i],
			_draw_calls[i],
			_primitives[i],
			_chunks_built[i],
			_build_ms[i],
			_fauna_count[i],
			_biomes[_biome_index[i]],
		]
	)


func _header() -> Dictionary:
	var version := Engine.get_version_info()
	return {
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(),
		"resolution":
		[get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"render_scale": get_viewport().scaling_3d_scale,
		"vsync": Settings.vsync,
		"preset": String(Settings.quality.id),
		"seed": SEED,
		"distance_m": distance,
		"speed_mps": speed,
		"godot": "%s.%s.%s.%s" % [version.major, version.minor, version.patch, version.status],
		"os": OS.get_name(),
		"date": Time.get_datetime_string_from_system(),
	}


func _default_path() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace(
		"T", "-"
	)
	return "user://perf/%s_%s.csv" % [stamp, preset]


static func _arg(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


static func _arg_float(prefix: String, fallback: float) -> float:
	var text := _arg(prefix, "")
	return text.to_float() if text.is_valid_float() else fallback
