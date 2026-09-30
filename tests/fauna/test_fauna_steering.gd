## Tests for [FaunaSteering] (pure).
extends GdUnitTestSuite

const EAST := Vector3(1, 0, 0)


func test_keeps_the_desired_direction_when_clear() -> void:
	var dir := FaunaSteering.clear_direction(EAST, func(_d: Vector3) -> bool: return true)
	assert_vector(dir).is_equal_approx(EAST, Vector3.ONE * 1e-5)


func test_turns_as_little_as_possible_around_a_blockage() -> void:
	# Blocked within 50° of east.
	var clear := func(d: Vector3) -> bool: return rad_to_deg(d.angle_to(EAST)) > 50.0
	var dir := FaunaSteering.clear_direction(EAST, clear)
	assert_float(rad_to_deg(dir.angle_to(EAST))).is_equal_approx(60.0, 0.01)


func test_everything_blocked_means_stop() -> void:
	var dir := FaunaSteering.clear_direction(EAST, func(_d: Vector3) -> bool: return false)
	assert_vector(dir).is_equal(Vector3.ZERO)


func test_separation_pushes_away_from_close_neighbours_only() -> void:
	var push := FaunaSteering.separation(
		Vector3.ZERO, PackedVector3Array([Vector3(0.5, 0, 0), Vector3(10, 0, 0)]), 2.0
	)
	assert_float(push.x).is_less(0.0)
	assert_float(push.length()).is_less_equal(1.0)
	(
		assert_vector(
			FaunaSteering.separation(Vector3.ZERO, PackedVector3Array([Vector3(3, 0, 0)]), 2.0)
		)
		. is_equal(Vector3.ZERO)
	)
