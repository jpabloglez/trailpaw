class_name WorldStreamer
extends Node3D
## Streams [TerrainChunk]s around a target: generates [ChunkData] on worker threads and
## turns finished data into nodes on the main thread within a per-frame time budget.
##
## Loads every chunk within [member StreamingSettings.load_radius] of the target's chunk
## (LOD 0 with collision near the target, coarse LOD further out),
## nearest first (ties go to chunks in the view direction), and only drops chunks beyond
## [member StreamingSettings.unload_radius], so moving back and forth near a border never
## thrashes. Chunk nodes are pooled. Results for chunks that are no longer wanted are
## discarded when they arrive.
## [br][br]
## Budget (main thread, per frame): re-planning only when the target changes chunk
## (O(load_radius²)); polling at most [member StreamingSettings.max_tasks_in_flight] tasks;
## building for at most [member StreamingSettings.build_budget_ms] (at least one chunk).
## No per-frame allocations in the steady state.

## Emitted at most once per frame when the loaded set, a chunk's LOD or chunk positions
## changed (after building or unloading, and after a floating-origin rebase).
signal chunks_changed

## Group of nodes providing [code]get_debug_lines()[/code] for the F3 overlay.
const DEBUG_LINES_GROUP: StringName = &"debug_lines"

## Global shader uniform holding [member TerrainSettings.sea_level] (declared in
## [code]project.godot[/code]). Absolute height: floating-origin rebases never shift Y.
const WATER_LEVEL_PARAM: StringName = &"water_level"
## Global shader uniform with the packed [WindSettings] (see [code]foliage.gdshader[/code]).
const WIND_PARAM: StringName = &"wind"

## Terrain shape and chunk geometry.
@export var terrain: TerrainSettings
## Radii, budget and concurrency.
@export var streaming: StreamingSettings
## Node the terrain streams around (the player or a debug camera).
@export var target: Node3D
## Scene instanced for each chunk (must have a [TerrainChunk] root).
@export var chunk_scene: PackedScene
## Material applied to every chunk surface.
@export var material: Material
## Wind published to foliage shaders (optional).
@export var wind: WindSettings
## Optional recolouring of imported vegetation materials.
@export var vegetation_palette: VegetationPalette

## Multiplier for every vegetation density; follows [code]Settings.quality[/code].
var vegetation_density: float = 1.0

var _changed: bool = false
var _generation: int = 0
var _scatterer: VegetationScatterer
var _library: VegetationLibrary
var _center: Vector2i = Vector2i.ZERO
var _has_center: bool = false
var _desired: Dictionary[Vector2i, int] = {}
var _loaded: Dictionary[Vector2i, TerrainChunk] = {}
var _queue: Array[Vector2i] = []
var _in_flight: Array[ChunkJob] = []
var _ready_jobs: Array[ChunkJob] = []
var _pool: Array[TerrainChunk] = []
var _last_build_ms: float = 0.0
var _max_build_ms: float = 0.0
var _max_chunk_ms: float = 0.0
var _last_frame_built: int = 0
var _total_built: int = 0
var _no_filter: Array[StringName] = []


func _ready() -> void:
	var problems := PackedStringArray()
	if terrain == null or not terrain.is_valid():
		problems.append("invalid terrain settings")
	if streaming == null or not streaming.is_valid():
		problems.append("invalid streaming settings")
	if chunk_scene == null:
		problems.append("no chunk_scene")
	if not problems.is_empty():
		push_error("WorldStreamer %s: %s" % [get_path(), ", ".join(problems)])
		set_process(false)
		return
	add_to_group(DEBUG_LINES_GROUP)
	if terrain.biomes != null:
		# Immutable snapshot of the vegetation tables, shared read-only by every job.
		_scatterer = VegetationScatterer.new(terrain.biomes)
		_library = VegetationLibrary.new(terrain.biomes, vegetation_palette)
	if wind != null:
		RenderingServer.global_shader_parameter_set(WIND_PARAM, wind.as_uniform())
	# Shaders (terrain shores, underwater tint) need the absolute water height.
	RenderingServer.global_shader_parameter_set(WATER_LEVEL_PARAM, terrain.sea_level)
	GameState.water_level = terrain.sea_level
	EventBus.origin_shifted.connect(_on_origin_shifted)
	vegetation_density = Settings.quality.vegetation_density
	Settings.quality_changed.connect(_on_quality_changed)


func _process(_delta: float) -> void:
	if target == null:
		return
	var center := _target_chunk()
	if not _has_center or center != _center:
		_replan(center)
	_collect_finished()
	_build_ready()
	_submit_tasks()
	if _changed:
		_changed = false
		chunks_changed.emit()


func _exit_tree() -> void:
	# Every WorkerThreadPool task must be waited on, even if its result is discarded.
	for job in _in_flight:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_in_flight.clear()


## Whether the chunk at [param coord] currently has a node with geometry.
func is_loaded(coord: Vector2i) -> bool:
	return _loaded.has(coord)


## Coordinates of all loaded chunks.
func loaded_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	coords.assign(_loaded.keys())
	return coords


## The loaded chunk node at [param coord], or [code]null[/code].
func get_chunk(coord: Vector2i) -> TerrainChunk:
	return _loaded.get(coord)


## Whether there is collision under local position [param local_position].
func is_ready_at(local_position: Vector3) -> bool:
	var chunk: TerrainChunk = _loaded.get(_chunk_for_local(local_position))
	return chunk != null and chunk.has_collision()


## Whether nothing is queued, generating or waiting to be built.
func is_idle() -> bool:
	return _queue.is_empty() and _in_flight.is_empty() and _ready_jobs.is_empty()


## Streaming statistics for debugging and budget checks.
func stats() -> Dictionary:
	return {
		"loaded": _loaded.size(),
		"queued": _queue.size(),
		"in_flight": _in_flight.size(),
		"ready": _ready_jobs.size(),
		"pooled": _pool.size(),
		"last_build_ms": _last_build_ms,
		"max_build_ms": _max_build_ms,
		"max_chunk_ms": _max_chunk_ms,
		"last_frame_built": _last_frame_built,
		"total_built": _total_built,
	}


## Food kinds that get interaction targets: the diet of the [member target]'s species when
## it has one (an [Animal]), otherwise every kind (empty).
func edible_kinds() -> Array[StringName]:
	var animal := target as Animal
	if animal != null and animal.movement != null and animal.movement.species != null:
		return animal.movement.species.diet
	return _no_filter


## Lines for the F3 debug overlay.
func get_debug_lines() -> PackedStringArray:
	return PackedStringArray(
		[
			(
				"chunks %d loaded  %d queued  %d generating"
				% [_loaded.size(), _queue.size(), _in_flight.size()]
			),
			(
				"build %.2f ms last  %.2f ms max  (budget %.1f)"
				% [_last_build_ms, _max_build_ms, streaming.build_budget_ms]
			),
		]
	)


## Local position of the corner of chunk [param coord].
func chunk_origin(coord: Vector2i) -> Vector3:
	var local := coord - GameState.origin_chunk
	return Vector3(local.x, 0.0, local.y) * terrain.chunk_size


func _target_chunk() -> Vector2i:
	return _chunk_for_local(target.global_position)


func _chunk_for_local(local_position: Vector3) -> Vector2i:
	var local := StreamingPlan.chunk_at(local_position.x, local_position.z, terrain.chunk_size)
	return local + GameState.origin_chunk


## Regenerates every loaded chunk (e.g. after a quality change). Chunks stay visible until
## their replacement is built, like LOD changes.
func refresh() -> void:
	_generation += 1
	if _has_center:
		_replan(_center)


func _on_quality_changed(preset: QualityPreset) -> void:
	vegetation_density = preset.vegetation_density
	refresh()


func _on_origin_shifted(_offset: Vector3) -> void:
	# Re-derive every chunk position from its exact integer coordinate (no drift).
	for coord: Vector2i in _loaded:
		_loaded[coord].position = chunk_origin(coord)
	_changed = true


func _replan(center: Vector2i) -> void:
	_center = center
	_has_center = true
	for coord: Vector2i in _loaded.keys():
		if StreamingPlan.should_unload(coord, center, streaming):
			_release(coord)
	var current_lods: Dictionary[Vector2i, int] = {}
	for coord: Vector2i in _loaded:
		current_lods[coord] = _loaded[coord].lod
	_desired = StreamingPlan.desired_chunks(center, streaming, current_lods)
	_queue.clear()
	for coord: Vector2i in _desired:
		if not _has_lod(coord, _desired[coord]) and not _is_in_flight(coord, _desired[coord]):
			_queue.append(coord)
	StreamingPlan.sort_by_priority(_queue, center, _view_direction())


func _collect_finished() -> void:
	for i in range(_in_flight.size() - 1, -1, -1):
		var job := _in_flight[i]
		if WorkerThreadPool.is_task_completed(job.task_id):
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			_in_flight.remove_at(i)
			_ready_jobs.append(job)


func _build_ready() -> void:
	var start := Time.get_ticks_usec()
	var budget_us := streaming.build_budget_ms * 1000.0
	var built := 0
	while not _ready_jobs.is_empty():
		if built > 0 and float(Time.get_ticks_usec() - start) >= budget_us:
			break
		var job: ChunkJob = _ready_jobs.pop_front()
		if (
			_desired.get(job.coord, -1) != job.lod
			or job.generation != _generation
			or _has_lod(job.coord, job.lod)
		):
			continue  # stale: the target moved on (or the LOD changed) while generating
		# A chunk changing LOD is rebuilt in place, so it never disappears for a frame.
		var chunk_start := Time.get_ticks_usec()
		var chunk: TerrainChunk = _loaded.get(job.coord)
		if chunk == null:
			chunk = _acquire()
		chunk.position = chunk_origin(job.coord)
		chunk.apply(job.data, material, _library, edible_kinds())
		chunk.generation = _generation
		_max_chunk_ms = maxf(_max_chunk_ms, float(Time.get_ticks_usec() - chunk_start) / 1000.0)
		_loaded[job.coord] = chunk
		built += 1
		_changed = true
	_last_frame_built = built
	if built > 0:
		_last_build_ms = float(Time.get_ticks_usec() - start) / 1000.0
		_max_build_ms = maxf(_max_build_ms, _last_build_ms)
		_total_built += built


func _submit_tasks() -> void:
	while _in_flight.size() < streaming.max_tasks_in_flight and not _queue.is_empty():
		var coord: Vector2i = _queue.pop_front()
		if not _desired.has(coord) or _has_lod(coord, _desired[coord]):
			continue
		var job := (
			ChunkJob
			. new(
				coord,
				_desired[coord],
				terrain.duplicate(),
				GameState.world_seed,
				_scatterer,
				vegetation_density,
			)
		)
		job.generation = _generation
		job.task_id = WorkerThreadPool.add_task(job.run, false, "terrain chunk")
		_in_flight.append(job)


func _has_lod(coord: Vector2i, lod: int) -> bool:
	var chunk: TerrainChunk = _loaded.get(coord)
	return chunk != null and chunk.lod == lod and chunk.generation == _generation


func _is_in_flight(coord: Vector2i, lod: int) -> bool:
	for job in _in_flight:
		if job.coord == coord and job.lod == lod and job.generation == _generation:
			return true
	for job in _ready_jobs:
		if job.coord == coord and job.lod == lod and job.generation == _generation:
			return true
	return false


func _acquire() -> TerrainChunk:
	if not _pool.is_empty():
		return _pool.pop_back()
	var chunk := chunk_scene.instantiate() as TerrainChunk
	add_child(chunk)
	return chunk


func _release(coord: Vector2i) -> void:
	var chunk: TerrainChunk = _loaded[coord]
	_loaded.erase(coord)
	chunk.reset()
	_pool.append(chunk)
	_changed = true


func _view_direction() -> Vector2:
	var camera := get_viewport().get_camera_3d()
	var basis := camera.global_basis if camera != null else target.global_basis
	var forward := Vector2(-basis.z.x, -basis.z.z)
	return forward.normalized() if forward.length_squared() > 1e-6 else Vector2.ZERO
