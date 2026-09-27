class_name StreamingSettings
extends Resource
## Tunables for [WorldStreamer]: which chunks are loaded and how much main-thread time
## building them may take. Distances are in chunks, measured between chunk grid
## coordinates. Defaults are neutral: values come from
## [code]data/world/streaming_settings.tres[/code].

## Chunks within this distance of the target's chunk are loaded.
@export_range(1, 16) var load_radius: int = 0
## Loaded chunks are only dropped beyond this distance (hysteresis; > load_radius).
@export_range(1, 20) var unload_radius: int = 0
## Main-thread time per frame for turning finished chunk data into nodes. At least one
## chunk is built per frame when any is ready.
@export_range(0.1, 16.0, 0.1, "suffix:ms") var build_budget_ms: float = 0.0
## Maximum chunk generation tasks running on worker threads at once.
@export_range(1, 32) var max_tasks_in_flight: int = 0


## Returns human-readable problems with the tunables; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if load_radius < 1:
		errors.append("load_radius must be >= 1")
	if unload_radius <= load_radius:
		errors.append("unload_radius must be > load_radius")
	if build_budget_ms <= 0.0:
		errors.append("build_budget_ms must be > 0")
	if max_tasks_in_flight < 1:
		errors.append("max_tasks_in_flight must be >= 1")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
