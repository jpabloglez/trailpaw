## Tests for [LocomotionModel]: camera-relative input, speed cap, arc turning and gaits.
extends GdUnitTestSuite

const SPECIES_PATH: String = "res://data/species/placeholder.tres"
const FORWARD := Vector2(0.0, -1.0)
const EPSILON: float = 1e-4

var _species: AnimalSpecies


func before() -> void:
	_species = load(SPECIES_PATH)


func _assert_vec(actual: Vector3, expected: Vector3) -> void:
	assert_vector(actual).is_equal_approx(expected, Vector3.ONE * EPSILON)


# --- camera-relative movement -------------------------------------------------------


func test_forward_input_follows_unrotated_camera() -> void:
	var dir := LocomotionModel.camera_relative_direction(FORWARD, Basis.IDENTITY)
	_assert_vec(dir, Vector3.FORWARD)


func test_forward_input_follows_camera_yaw() -> void:
	var yawed := Basis(Vector3.UP, PI / 2.0)  # camera looks towards -X
	_assert_vec(LocomotionModel.camera_relative_direction(FORWARD, yawed), Vector3.LEFT)
	var behind := Basis(Vector3.UP, PI)  # camera looks towards +Z
	_assert_vec(LocomotionModel.camera_relative_direction(FORWARD, behind), Vector3.BACK)


func test_right_input_is_camera_right() -> void:
	var yawed := Basis(Vector3.UP, PI / 2.0)
	var dir := LocomotionModel.camera_relative_direction(Vector2.RIGHT, yawed)
	_assert_vec(dir, Vector3.FORWARD)


func test_pitched_camera_still_moves_on_ground_plane() -> void:
	var pitched := Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, deg_to_rad(-60.0))
	var dir := LocomotionModel.camera_relative_direction(FORWARD, pitched)
	assert_float(dir.y).is_equal_approx(0.0, EPSILON)
	assert_float(dir.length()).is_equal_approx(1.0, EPSILON)


func test_camera_looking_straight_down_uses_its_up_vector() -> void:
	var down := Basis(Vector3.RIGHT, -PI / 2.0)
	var dir := LocomotionModel.camera_relative_direction(FORWARD, down)
	_assert_vec(dir, Vector3.FORWARD)


func test_diagonal_input_is_capped_at_unit_length() -> void:
	var dir := LocomotionModel.camera_relative_direction(Vector2(1.0, -1.0), Basis.IDENTITY)
	assert_float(dir.length()).is_equal_approx(1.0, EPSILON)


# --- speed ----------------------------------------------------------------------------


func test_target_speed_trots_by_default_and_runs_when_sprinting() -> void:
	assert_float(LocomotionModel.target_speed(1.0, false, 0.0, _species)).is_equal(
		_species.trot_speed
	)
	assert_float(LocomotionModel.target_speed(1.0, true, 0.0, _species)).is_equal(
		_species.run_speed
	)
	assert_float(LocomotionModel.target_speed(0.0, true, 0.0, _species)).is_equal(0.0)


func test_facing_away_lowers_target_speed() -> void:
	var straight := LocomotionModel.target_speed(1.0, true, 0.0, _species)
	var reversed := LocomotionModel.target_speed(1.0, true, PI, _species)
	assert_float(reversed).is_equal_approx(straight * (1.0 - _species.turn_slowdown), EPSILON)


func test_speed_never_exceeds_species_max() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var yaw := 0.0
	var speed := 0.0
	for i in 10000:
		var input := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI))
		var delta := rng.randf_range(0.0, 0.5)
		var control := rng.randf_range(0.0, 1.0)
		var desired := LocomotionModel.camera_relative_direction(input, basis)
		yaw = LocomotionModel.step_heading(yaw, desired, speed, _species, delta, control)
		var error := LocomotionModel.heading_error(yaw, desired)
		var target := LocomotionModel.target_speed(
			desired.length(), rng.randf() < 0.5, error, _species
		)
		speed = LocomotionModel.step_speed(speed, target, _species, delta, control)
		if speed > _species.run_speed + EPSILON or speed < 0.0:
			fail("step %d: speed %f outside [0, %f]" % [i, speed, _species.run_speed])
			return
	assert_float(speed).is_between(0.0, _species.run_speed)


func test_acceleration_and_deceleration_rates() -> void:
	var up := LocomotionModel.step_speed(0.0, 10.0, _species, 0.1)
	assert_float(up).is_equal_approx(_species.acceleration * 0.1, EPSILON)
	var down := LocomotionModel.step_speed(4.0, 0.0, _species, 0.1)
	assert_float(down).is_equal_approx(4.0 - _species.deceleration * 0.1, EPSILON)


# --- turning --------------------------------------------------------------------------


func test_turn_is_limited_by_slow_rate_when_standing() -> void:
	var yaw := LocomotionModel.step_heading(0.0, Vector3.LEFT, 0.0, _species, 0.1)
	assert_float(yaw).is_equal_approx(_species.turn_rate_slow * 0.1, EPSILON)


func test_turn_is_wider_at_run_speed() -> void:
	var yaw := LocomotionModel.step_heading(0.0, Vector3.LEFT, _species.run_speed, _species, 0.1)
	assert_float(yaw).is_equal_approx(_species.turn_rate_fast * 0.1, EPSILON)


func test_turn_reaches_target_without_overshoot() -> void:
	var yaw := LocomotionModel.step_heading(0.0, Vector3.LEFT, 0.0, _species, 10.0)
	assert_float(yaw).is_equal_approx(PI / 2.0, EPSILON)


func test_turn_takes_the_short_way_round() -> void:
	# From facing just left of +Z to just right of +Z: crossing ±PI, not through 0.
	var start := PI - 0.1
	var target_dir := LocomotionModel.forward_for_yaw(-PI + 0.1)
	var yaw := LocomotionModel.step_heading(start, target_dir, 0.0, _species, 0.01)
	assert_float(absf(yaw)).is_greater(start)


func test_air_control_scales_turning() -> void:
	var yaw := LocomotionModel.step_heading(0.0, Vector3.LEFT, 0.0, _species, 0.1, 0.5)
	assert_float(yaw).is_equal_approx(_species.turn_rate_slow * 0.1 * 0.5, EPSILON)


func test_no_direction_keeps_heading() -> void:
	var yaw := LocomotionModel.step_heading(1.0, Vector3.ZERO, 0.0, _species, 0.1)
	assert_float(yaw).is_equal(1.0)


# --- gaits and jump -------------------------------------------------------------------


func test_gait_thresholds() -> void:
	assert_int(LocomotionModel.gait_for_speed(0.0, _species)).is_equal(LocomotionModel.Gait.IDLE)
	assert_int(LocomotionModel.gait_for_speed(_species.walk_speed, _species)).is_equal(
		LocomotionModel.Gait.WALK
	)
	assert_int(LocomotionModel.gait_for_speed(_species.trot_speed, _species)).is_equal(
		LocomotionModel.Gait.TROT
	)
	assert_int(LocomotionModel.gait_for_speed(_species.run_speed, _species)).is_equal(
		LocomotionModel.Gait.RUN
	)


func test_jump_velocity_reaches_jump_height() -> void:
	var gravity := 9.8
	var v := LocomotionModel.jump_velocity(_species.jump_height, gravity)
	assert_float(v * v / (2.0 * gravity)).is_equal_approx(_species.jump_height, EPSILON)
