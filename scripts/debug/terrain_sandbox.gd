class_name TerrainSandbox
extends Node3D
## Debug scene controller for the streamed terrain: seeds the world, wires the floating
## origin, keeps the animal frozen until there is collision under it, switches between the
## animal and a free-fly camera ([code]toggle_free_fly[/code], F4) and runs the automated
## straight-line streaming probe.
##
## Probe: [code]godot --headless --path . res://scenes/debug/terrain_sandbox.tscn --
## --auto-travel=10000 [--auto-speed=30][/code] flies the free camera along +X for the given
## distance (m), then prints a report and quits with 0 (within budgets) or 1.

## Main-thread time a single frame may spend on streaming before it counts as a spike.
const SPIKE_MS: float = 4.0
## Height the probe camera keeps above the terrain.
const PROBE_ALTITUDE: float = 3.0
## Default probe speed (m/s): four times the placeholder animal's run speed.
const DEFAULT_PROBE_SPEED: float = 30.0
## Height above the terrain the animal is dropped from when it is released.
const SPAWN_CLEARANCE: float = 0.5

## World seed for this session.
@export var world_seed: int = 12345
## Terrain streamer.
@export var streamer: WorldStreamer
## Player animal.
@export var animal: Animal
## Orbit camera following the animal.
@export var camera_rig: CameraRig
## Debug fly camera.
@export var free_fly: FreeFlyCamera

var _animal_frozen: bool = true
var _sampler: HeightSampler
var _probe: Dictionary = {}
# Packed arrays are value types: keep frame times in a member, not inside the dictionary.
var _probe_frame_ms := PackedFloat32Array()


func _ready() -> void:
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)
	GameState.world_seed = world_seed
	FloatingOrigin.reset()
	FloatingOrigin.configure(streamer.terrain.chunk_size, streamer.streaming.rebase_distance)
	_sampler = HeightSampler.new(streamer.terrain, world_seed)
	_freeze_animal(true)
	_use_free_fly(false)
	var distance := _user_arg_float("--auto-travel=", 0.0)
	if distance > 0.0:
		_start_probe(distance, _user_arg_float("--auto-speed=", DEFAULT_PROBE_SPEED))


func _exit_tree() -> void:
	FloatingOrigin.reset()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_free_fly") and _probe.is_empty():
		toggle_free_fly()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _animal_frozen and not free_fly.active and streamer.is_ready_at(animal.position):
		_release_animal()
	if not _probe.is_empty():
		_probe_step(delta)


## Switches control (and streaming focus) between the animal and the free-fly camera.
func toggle_free_fly() -> void:
	_use_free_fly(not free_fly.active)


## Whether the animal is waiting for terrain collision (or parked during free-fly).
func is_animal_frozen() -> bool:
	return _animal_frozen


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	var target := streamer.target
	var absolute: Vector3 = GameState.absolute_position(target.global_position)
	return PackedStringArray(
		[
			(
				"mode %s  seed %d"
				% ["free-fly (F4)" if free_fly.active else "animal (F4)", world_seed]
			),
			"abs %.1f, %.1f, %.1f" % [absolute.x, absolute.y, absolute.z],
			"origin chunk %s" % GameState.origin_chunk,
		]
	)


func _use_free_fly(enabled: bool) -> void:
	if enabled:
		free_fly.take_transform(camera_rig.camera.global_transform)
		_freeze_animal(true)
	free_fly.active = enabled
	camera_rig.camera.current = not enabled
	var focus: Node3D = free_fly if enabled else animal
	streamer.target = focus
	FloatingOrigin.track(focus)


func _freeze_animal(frozen: bool) -> void:
	_animal_frozen = frozen
	animal.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT


func _release_animal() -> void:
	var absolute: Vector3 = GameState.absolute_position(animal.position)
	animal.position.y = _sampler.height_at(absolute.x, absolute.z) + SPAWN_CLEARANCE
	animal.velocity = Vector3.ZERO
	animal.reset_physics_interpolation()
	_freeze_animal(false)


# --- automated probe ------------------------------------------------------------------


func _start_probe(distance: float, speed: float) -> void:
	_use_free_fly(true)
	var start: Vector3 = GameState.absolute_position(free_fly.global_position)
	_probe = {
		"distance": distance,
		"speed": speed,
		"start_x": start.x,
		"started": false,
		"frames": 0,
		"spikes": 0,
		"holes": 0,
		"collision_gaps": 0,
		"rebases": 0,
		"build_ms_max": 0.0,
		"process_ms_sum": 0.0,
		"physics_ms_sum": 0.0,
	}
	EventBus.origin_shifted.connect(func(_offset: Vector3) -> void: _probe["rebases"] += 1)
	_probe_frame_ms.clear()
	print("[probe] %.0f m along +X at %.1f m/s (seed %d)" % [distance, speed, world_seed])


func _probe_step(delta: float) -> void:
	var target := free_fly.global_position
	var absolute: Vector3 = GameState.absolute_position(target)
	free_fly.global_position.y = _sampler.height_at(absolute.x, absolute.z) + PROBE_ALTITUDE
	if not _probe["started"]:
		# Wait for the initial load before measuring (warm-up is not part of travel).
		if streamer.is_idle() and streamer.is_ready_at(target):
			_probe["started"] = true
			free_fly.start_autopilot(Vector3(_probe["speed"], 0.0, 0.0))
		return
	var stats := streamer.stats()
	var built_ms: float = stats["last_build_ms"] if stats["last_frame_built"] > 0 else 0.0
	_probe["frames"] += 1
	_probe_frame_ms.append(delta * 1000.0)
	_probe["process_ms_sum"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_probe["physics_ms_sum"] += (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_probe["build_ms_max"] = maxf(_probe["build_ms_max"], built_ms)
	if built_ms > SPIKE_MS:
		_probe["spikes"] += 1
		_probe["spike_chunks"] = maxi(_probe.get("spike_chunks", 0), stats["last_frame_built"])
	var size := streamer.terrain.chunk_size
	if not streamer.is_loaded(StreamingPlan.chunk_at(absolute.x, absolute.z, size)):
		_probe["holes"] += 1
	if not streamer.is_ready_at(target):
		_probe["collision_gaps"] += 1
	if absolute.x - float(_probe["start_x"]) >= float(_probe["distance"]):
		_finish_probe(absolute)


func _finish_probe(absolute: Vector3) -> void:
	free_fly.stop_autopilot()
	var frames := _probe_frame_ms.duplicate()
	frames.sort()
	var ok: bool = _probe["spikes"] == 0 and _probe["holes"] == 0 and _probe["collision_gaps"] == 0
	var lines := PackedStringArray(
		[
			(
				"[probe] travelled %.1f m (abs x %.1f) in %d frames"
				% [absolute.x - float(_probe["start_x"]), absolute.x, _probe["frames"]]
			),
			"[probe] rebases %d  origin chunk %s" % [_probe["rebases"], GameState.origin_chunk],
			(
				"[probe] streaming build ms: max %.3f  (budget %.1f, spike > %.1f: %d frames)"
				% [
					_probe["build_ms_max"],
					streamer.streaming.build_budget_ms,
					SPIKE_MS,
					_probe["spikes"]
				]
			),
			(
				"[probe] holes (chunk missing under target): %d  collision gaps: %d"
				% [_probe["holes"], _probe["collision_gaps"]]
			),
			(
				"[probe] frame ms p50 %.2f  p95 %.2f  p99 %.2f  max %.2f"
				% [
					_percentile(frames, 0.5),
					_percentile(frames, 0.95),
					_percentile(frames, 0.99),
					frames[frames.size() - 1] if frames.size() > 0 else 0.0
				]
			),
			(
				"[probe] avg main-thread process %.2f ms  physics %.2f ms per frame"
				% [
					float(_probe["process_ms_sum"]) / maxi(1, _probe["frames"]),
					float(_probe["physics_ms_sum"]) / maxi(1, _probe["frames"]),
				]
			),
			(
				"[probe] chunks built %d  pooled %d  most expensive single chunk %.3f ms"
				% [
					streamer.stats()["total_built"],
					streamer.stats()["pooled"],
					streamer.stats()["max_chunk_ms"],
				]
			),
			"[probe] most chunks built in one spike frame: %d" % _probe.get("spike_chunks", 0),
			"[probe] RESULT %s" % ("PASS" if ok else "FAIL"),
		]
	)
	print("\n".join(lines))
	_probe.clear()
	get_tree().quit(0 if ok else 1)


static func _percentile(sorted_values: PackedFloat32Array, q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	return sorted_values[clampi(int(q * (sorted_values.size() - 1)), 0, sorted_values.size() - 1)]


static func _user_arg_float(prefix: String, fallback: float) -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix).to_float()
	return fallback
