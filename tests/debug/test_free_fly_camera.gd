## Tests for [FreeFlyCamera]: flight maths, speed steps, activation and autopilot.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/debug/free_fly_camera.tres"
const EPSILON: float = 1e-4

var _settings: FreeFlyCameraSettings


func before() -> void:
	_settings = load(SETTINGS_PATH)


func _make_camera() -> FreeFlyCamera:
	var cam: FreeFlyCamera = auto_free(FreeFlyCamera.new())
	cam.settings = _settings
	add_child(cam)
	return cam


func test_settings_are_valid() -> void:
	assert_array(Array(_settings.get_validation_errors())).is_empty()


func test_forward_input_flies_along_view_direction() -> void:
	var looking_left := Basis(Vector3.UP, PI / 2.0)
	var v := FreeFlyCamera.fly_velocity(Vector2(0.0, -1.0), looking_left, 10.0)
	assert_vector(v).is_equal_approx(Vector3(-10.0, 0.0, 0.0), Vector3.ONE * EPSILON)


func test_pitched_view_flies_upwards() -> void:
	var looking_up := Basis(Vector3.RIGHT, PI / 4.0)
	var v := FreeFlyCamera.fly_velocity(Vector2(0.0, -1.0), looking_up, 1.0)
	assert_float(v.y).is_greater(0.5)


func test_diagonal_input_does_not_exceed_speed() -> void:
	var v := FreeFlyCamera.fly_velocity(Vector2(1.0, -1.0), Basis.IDENTITY, 10.0)
	assert_float(v.length()).is_equal_approx(10.0, EPSILON)


func test_speed_steps_are_clamped() -> void:
	var up := FreeFlyCamera.step_speed(_settings.base_speed, 1, _settings)
	assert_float(up).is_equal_approx(_settings.base_speed * _settings.speed_step, EPSILON)
	assert_float(FreeFlyCamera.step_speed(1e9, 1, _settings)).is_equal(_settings.max_speed)
	assert_float(FreeFlyCamera.step_speed(0.001, -1, _settings)).is_equal(_settings.min_speed)


func test_activation_controls_current_camera() -> void:
	var cam := _make_camera()
	assert_bool(cam.current).is_false()
	cam.active = true
	assert_bool(cam.current).is_true()
	cam.active = false
	assert_bool(cam.current).is_false()


func test_look_clamps_pitch() -> void:
	var cam := _make_camera()
	cam.look(Vector2(0.0, -1e6))
	assert_float(cam.rotation.x).is_less_equal(PI * 0.49 + EPSILON)


func test_autopilot_moves_at_constant_velocity() -> void:
	var cam := _make_camera()
	cam.active = true
	cam.start_autopilot(Vector3(30.0, 0.0, 0.0))
	cam._process(0.5)
	assert_vector(cam.global_position).is_equal_approx(
		Vector3(15.0, 0.0, 0.0), Vector3.ONE * EPSILON
	)
	cam.stop_autopilot()
	cam._process(0.5)
	assert_vector(cam.global_position).is_equal_approx(
		Vector3(15.0, 0.0, 0.0), Vector3.ONE * EPSILON
	)


func test_joins_origin_shiftable_group() -> void:
	assert_bool(_make_camera().is_in_group(FloatingOrigin.SHIFTABLE_GROUP)).is_true()
