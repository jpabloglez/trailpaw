class_name WaterScent
extends RefCounted
## Long-range water search for sniffing: the nearest point within [member radius] where the
## terrain lies at least [member min_depth] under the water surface, found from the height
## function alone (no loaded chunks needed), so it works far beyond the streamed area.
##
## Rings every [member step] metres are walked outwards with about [member step] metres of arc
## between samples; the first ring with water wins, and the hit is pulled back along its ray to
## the shore (1 m steps). Run [method run] on a [WorkerThreadPool] task: the job owns its
## [HeightSampler] (built on the main thread, as [ChunkJob] does) and the main thread reads
## [member result] only after the task completes.
## [br][br]
## Budget: worst case (no water) ≈ π·radius²/step² samples — about 12 k for 1 km in 16 m steps,
## tens of milliseconds, on a worker thread only. Nothing runs per frame.

## Shore refinement step (m).
const SHORE_STEP: float = 1.0

## Search origin (absolute X, Z).
var origin: Vector2
## Search radius (m).
var radius: float
## Distance between rings and between samples on a ring (m).
var step: float
## Water surface height (absolute Y).
var water_level: float
## Minimum water depth that counts (m).
var min_depth: float
## Nearest water (absolute; Y = the water surface), or [constant Vector3.INF] when none. Set by
## [method run].
var result: Vector3 = Vector3.INF
## [WorkerThreadPool] task id, set by the submitter.
var task_id: int = -1

var _sampler: HeightSampler


func _init(
	sampler: HeightSampler,
	from: Vector2,
	search_radius: float,
	search_step: float,
	surface: float,
	depth: float
) -> void:
	_sampler = sampler
	origin = from
	radius = search_radius
	step = search_step
	water_level = surface
	min_depth = depth


## Worker-thread entry point: fills [member result].
func run() -> void:
	result = search()


## Searches now (on the calling thread) and returns the nearest water, or
## [constant Vector3.INF].
func search() -> Vector3:
	if is_inf(water_level) or step <= 0.0:
		return Vector3.INF
	var limit := water_level - min_depth
	var ring := step
	while ring <= radius + 0.001:
		var samples := maxi(8, ceili(TAU * ring / step))
		for i in samples:
			var angle := TAU * i / samples
			var direction := Vector2(cos(angle), sin(angle))
			var point := origin + direction * ring
			if _sampler.height_at(point.x, point.y) <= limit:
				return _shore(direction, ring)
		ring += step
	return Vector3.INF


# First point along [param direction] (from the previous ring out to [param ring]) that is deep
# enough: the near shore of the water the ring found.
func _shore(direction: Vector2, ring: float) -> Vector3:
	var limit := water_level - min_depth
	var distance := maxf(0.0, ring - step)
	while distance < ring:
		var point := origin + direction * distance
		if _sampler.height_at(point.x, point.y) <= limit:
			return Vector3(point.x, water_level, point.y)
		distance += SHORE_STEP
	var end := origin + direction * ring
	return Vector3(end.x, water_level, end.y)
