class_name ChunkJob
extends RefCounted
## One chunk generation task for [WorkerThreadPool]. The worker writes [member data]; the
## main thread reads it only after [method WorkerThreadPool.wait_for_task_completion],
## which is the synchronisation point. The job owns its [TerrainSettings] copy and a
## [HeightSampler] built on the main thread, so the worker never reads shared resources
## (biome [code].tres[/code] files are shared by all jobs). The optional
## [VegetationScatterer] is an immutable snapshot shared read-only by all jobs.

## Chunk to generate.
var coord: Vector2i
## LOD level to generate.
var lod: int
## Result, set by [method run] on the worker thread.
var data: ChunkData
## [WorkerThreadPool] task id, set by the submitter.
var task_id: int = -1
## Streamer generation this job belongs to (results of older generations are dropped).
var generation: int = 0

var _settings: TerrainSettings
var _sampler: HeightSampler
var _scatterer: VegetationScatterer
var _world_seed: int = 0
var _density_scale: float = 1.0


func _init(
	chunk_coord: Vector2i,
	chunk_lod: int,
	settings: TerrainSettings,
	world_seed: int,
	scatterer: VegetationScatterer = null,
	density_scale: float = 1.0
) -> void:
	coord = chunk_coord
	lod = chunk_lod
	_settings = settings
	_sampler = HeightSampler.new(settings, world_seed)
	_scatterer = scatterer
	_world_seed = world_seed
	_density_scale = density_scale


## Worker-thread entry point.
func run() -> void:
	data = ChunkGenerator.generate_with(
		coord, lod, _settings, _sampler, _scatterer, _world_seed, _density_scale
	)
