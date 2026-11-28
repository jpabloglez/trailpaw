## Tests for [SprintBursts]: free, burst-limited and blocked sprinting (ADR-012).
extends GdUnitTestSuite

const FULL := NeedEffect.Sprint.FULL
const BURSTS := NeedEffect.Sprint.BURSTS
const NONE := NeedEffect.Sprint.NONE


func _run(bursts: SprintBursts, seconds: float, limit: int, sprinting: bool) -> bool:
	var allowed := true
	for i in roundi(seconds * 10.0):
		allowed = bursts.step(0.1, limit, sprinting)
	return allowed


func test_full_always_allows_sprinting() -> void:
	var bursts := SprintBursts.new(4.0, 3.0)
	assert_bool(_run(bursts, 60.0, FULL, true)).is_true()


func test_none_never_allows_sprinting() -> void:
	var bursts := SprintBursts.new(4.0, 3.0)
	assert_bool(bursts.step(0.1, NONE, true)).is_false()
	assert_bool(bursts.step(0.1, NONE, false)).is_false()


func test_a_burst_lasts_its_seconds_then_rests() -> void:
	var bursts := SprintBursts.new(4.0, 3.0)
	assert_bool(_run(bursts, 3.9, BURSTS, true)).is_true()
	assert_bool(_run(bursts, 0.2, BURSTS, true)).is_false()
	assert_bool(bursts.is_resting()).is_true()
	assert_bool(_run(bursts, 2.8, BURSTS, true)).is_false()
	assert_bool(_run(bursts, 0.3, BURSTS, true)).is_true()
	assert_bool(bursts.is_resting()).is_false()
	assert_float(bursts.seconds_left()).is_greater(3.5)


func test_not_sprinting_refills_the_burst() -> void:
	var bursts := SprintBursts.new(4.0, 2.0)
	_run(bursts, 3.0, BURSTS, true)
	assert_float(bursts.seconds_left()).is_equal_approx(1.0, 1e-3)
	_run(bursts, 1.0, BURSTS, false)  # refills 4 s in 2 s
	assert_float(bursts.seconds_left()).is_equal_approx(3.0, 1e-3)
	_run(bursts, 5.0, BURSTS, false)
	assert_float(bursts.seconds_left()).is_equal(4.0)


func test_feeling_better_ends_the_rest_at_once() -> void:
	var bursts := SprintBursts.new(4.0, 3.0)
	_run(bursts, 4.5, BURSTS, true)
	assert_bool(bursts.is_resting()).is_true()
	assert_bool(bursts.step(0.1, FULL, true)).is_true()
	assert_bool(bursts.is_resting()).is_false()
	assert_float(bursts.seconds_left()).is_equal(4.0)
