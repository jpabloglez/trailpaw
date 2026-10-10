## Tests for the birds of prey (Phase 17: the golden eagle): they appear only over the
## mountains by day, soar in wide circles high above the ground, stay over the mountains as
## their circle drifts, cry now and then, leave at night or when the fox goes far away, and the
## journal can meet them.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const EAGLE: SoarerSettings = preload("res://data/critters/eagle.tres")
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")
const SEED: int = 12345
## On the mountain slope (seed 12345) and at the spawn meadow.
const MOUNTAIN := Vector3(4200.0, 60.0, -1290.0)

var _saved: Array = []


func before_test() -> void:
	_saved = [GameState.world_seed, GameState.game_minutes]
	GameState.world_seed = SEED
	GameState.game_minutes = 12.0 * 60.0


func after_test() -> void:
	GameState.world_seed = _saved[0]
	GameState.game_minutes = _saved[1]


func _soarers(at: Vector3) -> Array:
	var eager: SoarerSettings = EAGLE.duplicate()
	eager.appear_chance = 1.0  # appear at once (tests)
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	player.global_position = GameState.local_position(at)
	var soarers: Soarers = auto_free(Soarers.new())
	soarers.settings = eager
	soarers.terrain = TERRAIN
	soarers.player = player
	add_child(soarers)
	soarers.set_physics_process(false)
	soarers.set_process(false)
	return [soarers, player]


func _fly(soarers: Soarers, seconds: float) -> void:
	for t in int(seconds * Soarers.TICK_HZ):
		soarers.tick(1.0 / Soarers.TICK_HZ)
		for f in 4:
			soarers.advance(0.25 / Soarers.TICK_HZ)
	soarers.draw()


func test_none_over_the_meadow() -> void:
	var soarers: Soarers = _soarers(Vector3(0, 4, 0))[0]
	_fly(soarers, 30.0)
	assert_int(soarers.count()).is_equal(0)


func test_over_the_mountains_they_soar_in_high_wide_circles() -> void:
	var soarers: Soarers = _soarers(MOUNTAIN)[0]
	_fly(soarers, 10.0)
	assert_int(soarers.count()).is_between(1, EAGLE.max_soarers)
	for s in soarers.count():
		assert_float(soarers.height_above_ground(s)).is_between(20.0, EAGLE.soar_height.y + 40.0)
		var centre := soarers.centre_of(s)
		var here := GameState.absolute_position(soarers.position_of(s))
		var radius := Vector2(here.x - centre.x, here.z - centre.z).length()
		assert_float(radius).is_between(EAGLE.circle_radius.x - 0.5, EAGLE.circle_radius.y + 0.5)
	var before := soarers.position_of(0)
	_fly(soarers, 3.0)
	assert_float(soarers.position_of(0).distance_to(before)).is_greater(10.0)  # gliding on


func test_their_circles_stay_over_the_mountains() -> void:
	var soarers: Soarers = _soarers(MOUNTAIN)[0]
	soarers.settings.leave_distance = 5000.0  # keep the same birds all along
	for minute in 30:  # ≈ 2 km of drift: far more than the band is wide
		_fly(soarers, 60.0)
		for s in soarers.count():
			var centre := soarers.centre_of(s)
			assert_bool(soarers.is_their_sky(centre.x, centre.z)).is_true()
	assert_int(soarers.cries).is_greater(0)  # and now and then one cries


func test_at_the_edge_of_the_mountains_they_appear_over_the_mountains_only() -> void:
	var made := _soarers(MOUNTAIN)
	var soarers: Soarers = made[0]
	var player: Node3D = made[1]
	var ray := Vector2(MOUNTAIN.x, MOUNTAIN.z).normalized()
	var d := 3800.0
	while not soarers.is_their_sky(ray.x * d, ray.y * d):
		d += 5.0
	var edge := Vector3(ray.x, 0.0, ray.y) * (d + 20.0)  # just inside the band
	for round in 15:
		player.global_position = GameState.local_position(edge)
		_fly(soarers, 0.5)
		assert_int(soarers.count()).is_greater(0)
		for s in soarers.count():
			var centre := soarers.centre_of(s)
			assert_bool(soarers.is_their_sky(centre.x, centre.z)).is_true()
		player.global_position = GameState.local_position(edge + Vector3(3000, 0, 0))
		_fly(soarers, 0.5)  # they leave; new ones next round


func test_they_leave_at_night_and_when_the_fox_goes_far() -> void:
	var made := _soarers(MOUNTAIN)
	var soarers: Soarers = made[0]
	var player: Node3D = made[1]
	_fly(soarers, 5.0)
	assert_int(soarers.count()).is_greater(0)
	player.global_position = GameState.local_position(MOUNTAIN + Vector3(2000, 0, 0))
	_fly(soarers, 1.0)
	assert_int(soarers.count()).is_equal(0)
	player.global_position = GameState.local_position(MOUNTAIN)
	_fly(soarers, 5.0)
	assert_int(soarers.count()).is_greater(0)
	var cycle: DayNightCycle = auto_free(DayNightCycle.new())
	cycle.settings = load("res://data/world/day_night.tres")
	soarers.day_night = cycle
	GameState.game_minutes = 0.0
	_fly(soarers, 1.0)
	assert_int(soarers.count()).is_equal(0)
	assert_bool(soarers.is_day()).is_false()


func test_the_journal_meets_an_eagle_seen_overhead() -> void:
	var entry := JOURNAL.entry(&"golden_eagle")
	assert_object(entry).is_not_null()
	assert_int(entry.source).is_equal(JournalEntry.Source.SOARER)
	assert_array(entry.biome_ids(TERRAIN.biomes)).is_equal([&"mountains"] as Array[StringName])
	var made := _soarers(MOUNTAIN)
	var soarers: Soarers = made[0]
	var player: Node3D = made[1]
	_fly(soarers, 5.0)
	soarers.settings = EAGLE  # the journal knows the eagle by its settings
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	var tracker: EncounterTracker = auto_free(EncounterTracker.new())
	tracker.settings = JOURNAL
	tracker.player = player
	tracker.camera = camera
	tracker.soarers = soarers
	add_child(tracker)
	tracker.set_process(false)
	player.global_position = soarers.position_of(0) - Vector3(30.0, 50.0, 0.0)  # well below
	camera.global_position = player.global_position + Vector3.UP
	camera.look_at(soarers.position_of(0))  # looking up at it
	for t in 8:
		tracker.check(0.25)
	assert_bool(tracker.journal.is_seen(&"golden_eagle")).is_true()


func test_the_cry_is_high_and_falls() -> void:
	var cry := SynthSounds.cry()
	assert_float(cry.get_length()).is_between(0.5, 1.2)


func test_they_fit_their_budget() -> void:
	var soarers: Soarers = _soarers(MOUNTAIN)[0]
	_fly(soarers, 5.0)
	assert_int(soarers.count()).is_equal(EAGLE.max_soarers)
	var start := Time.get_ticks_usec()
	for t in 200:
		soarers.tick(1.0 / Soarers.TICK_HZ)
	var tick_ms := (Time.get_ticks_usec() - start) / 200.0 / 1000.0
	start = Time.get_ticks_usec()
	for f in 200:
		soarers.advance(1.0 / 60.0)
		soarers.draw()
	var frame_ms := (Time.get_ticks_usec() - start) / 200.0 / 1000.0
	assert_float(tick_ms).is_less(0.3)  # 4 Hz: a few height and biome samples
	assert_float(frame_ms).is_less(0.05)
