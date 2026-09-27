class_name ChunkJob
extends RefCounted
## One chunk generation task for [WorkerThreadPool]. The worker writes [member data]; the
## main thread reads it only after [method WorkerThreadPool.wait_for_task_completion],
## which is the synchronisation point. The job owns its [TerrainSettings] copy.

## Chunk to generate.
var coord: Vector2i
## LOD level to generate.
var lod: int
## Result, set by [method run] on the worker thread.
var data: ChunkData
## [WorkerThreadPool] task id, set by the submitter.
var task_id: int = -1

var _settings: TerrainSettings
var _world_seed: int


func _init(
	chunk_coord: Vector2i, chunk_lod: int, settings: TerrainSettings, world_seed: int
) -> void:
	coord = chunk_coord
	lod = chunk_lod
	_settings = settings
	_world_seed = world_seed


## Worker-thread entry point.
func run() -> void:
	data = ChunkGenerator.generate(coord, lod, _settings, _world_seed)
