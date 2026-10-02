## Tests for the long-range water search ([WaterScent]): finds the spawn meadow's nearest lake,
## stops at its radius, is deterministic and runs on a worker thread.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SNIFF: SniffSettings = preload("res://data/interaction/sniff.tres")
## Where a new game starts ([constant WorldController.NEW_GAME_POSITION]).
const SPAWN := Vector2(32.0, 32.0)
const SEED := 12345


func _scent(radius: float = SNIFF.scent_radius, surface: float = TERRAIN.sea_level) -> WaterScent:
	var sampler := HeightSampler.new(TERRAIN, SEED)
	return WaterScent.new(sampler, SPAWN, radius, SNIFF.scent_step, surface, SNIFF.scent_min_depth)


func test_finds_the_lake_nearest_to_the_spawn() -> void:
	var found := _scent().search()
	assert_bool(found == Vector3.INF).is_false()
	var offset := Vector2(found.x, found.z) - SPAWN
	# The M2 playtest note: the nearest lake is ≈ 770 m away, too far for the 25 m sniff.
	assert_float(offset.length()).is_between(700.0, 850.0)
	assert_float(found.y).is_equal(TERRAIN.sea_level)
	var sampler := HeightSampler.new(TERRAIN, SEED)
	var limit := TERRAIN.sea_level - SNIFF.scent_min_depth
	assert_float(sampler.height_at(found.x, found.z)).is_less_equal(limit)
	# It points at the near shore: a couple of metres back towards the animal is not deep yet.
	var back := Vector2(found.x, found.z) - offset.normalized() * 2.0
	assert_float(sampler.height_at(back.x, back.y)).is_greater(limit)


func test_the_lake_is_reachable_before_thirst_runs_out() -> void:
	var found := _scent().search()
	var thirst: NeedDefinition = load("res://data/needs/thirst.tres")
	var fox: AnimalSpecies = load("res://data/species/fox.tres")
	var trot_minutes := (Vector2(found.x, found.z) - SPAWN).length() / fox.trot_speed / 60.0
	var thirst_minutes := thirst.max_value / thirst.decay_per_minute
	assert_float(trot_minutes).is_less(thirst_minutes * 0.5)


func test_nothing_beyond_the_radius() -> void:
	assert_bool(_scent(500.0).search() == Vector3.INF).is_true()
	assert_bool(_scent(SNIFF.scent_radius, -500.0).search() == Vector3.INF).is_true()
	assert_bool(_scent(SNIFF.scent_radius, -INF).search() == Vector3.INF).is_true()


func test_same_world_same_answer() -> void:
	assert_that(_scent().search()).is_equal(_scent().search())


func test_runs_on_a_worker_thread() -> void:
	var scent := _scent()
	scent.task_id = WorkerThreadPool.add_task(scent.run)
	WorkerThreadPool.wait_for_task_completion(scent.task_id)
	assert_that(scent.result).is_equal(_scent().search())
