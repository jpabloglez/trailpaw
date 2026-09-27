## Tests for [CameraRig] maths, input handling and target following.
extends GdUnitTestSuite

const RIG_SCENE: String = "res://scenes/player/camera_rig.tscn"
const SETTINGS_PATH: String = "res://data/camera/default_camera_rig.tres"
const EPSILON: float = 1e-4

var _settings: CameraRigSettings


func before() -> void:
	_settings = load(SETTINGS_PATH)


func _make_rig(target: Node3D) -> CameraRig:
	var rig: CameraRig = auto_free(load(RIG_SCENE).instantiate())
	rig.target = target
	add_child(rig)
	return rig


func _make_target(pos: Vector3 = Vector3.ZERO) -> Node3D:
	var target: Node3D = auto_free(Node3D.new())
	target.position = pos
	add_child(target)
	return target


func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


# --- data -----------------------------------------------------------------------------


func test_default_settings_are_valid() -> void:
	assert_array(Array(_settings.get_validation_errors())).is_empty()


func test_unconfigured_settings_are_invalid() -> void:
	assert_bool(CameraRigSettings.new().is_valid()).is_false()


# --- pure maths -----------------------------------------------------------------------


func test_pitch_is_clamped_to_limits() -> void:
	var low := deg_to_rad(_settings.pitch_min_degrees)
	var high := deg_to_rad(_settings.pitch_max_degrees)
	assert_float(CameraRig.clamp_pitch(-PI, _settings)).is_equal_approx(low, EPSILON)
	assert_float(CameraRig.clamp_pitch(PI, _settings)).is_equal_approx(high, EPSILON)
	assert_float(CameraRig.clamp_pitch(0.0, _settings)).is_equal(0.0)


func test_zoom_is_clamped_to_limits() -> void:
	assert_float(CameraRig.step_zoom(_settings.zoom_min, -10.0, _settings)).is_equal(
		_settings.zoom_min
	)
	assert_float(CameraRig.step_zoom(_settings.zoom_max, 10.0, _settings)).is_equal(
		_settings.zoom_max
	)


func test_recentre_takes_the_short_way_round() -> void:
	# From just below +PI to just above -PI the short way crosses PI, not 0.
	var yaw := CameraRig.recentre_yaw(PI - 0.1, -PI + 0.1, 5.0, 0.016)
	assert_float(absf(yaw)).is_greater(PI - 0.1)


func test_recentre_converges_on_target_yaw() -> void:
	var yaw := 0.0
	for i in 600:
		yaw = CameraRig.recentre_yaw(yaw, 2.0, _settings.recentre_speed, 1.0 / 60.0)
	assert_float(yaw).is_equal_approx(2.0, 1e-3)


func test_smoothing_weight_is_frame_rate_independent() -> void:
	var one_step := CameraRig.smoothing_weight(10.0, 0.1)
	var two_steps := 1.0 - pow(1.0 - CameraRig.smoothing_weight(10.0, 0.05), 2.0)
	assert_float(two_steps).is_equal_approx(one_step, EPSILON)


# --- node behaviour -------------------------------------------------------------------


func test_rig_starts_at_target_pivot_with_default_zoom_and_pitch() -> void:
	var target := _make_target(Vector3(3.0, 0.0, -2.0))
	var rig := _make_rig(target)
	var pivot := Vector3(3.0, _settings.pivot_height, -2.0)
	assert_vector(rig.global_position).is_equal_approx(pivot, Vector3.ONE * EPSILON)
	assert_float(rig.zoom_target()).is_equal(_settings.zoom_default)
	assert_float(rig.pitch()).is_equal_approx(deg_to_rad(_settings.default_pitch_degrees), EPSILON)


func test_rig_follows_moving_target() -> void:
	var target := _make_target()
	var rig := _make_rig(target)
	target.global_position = Vector3(10.0, 0.0, 0.0)
	for i in 120:
		rig._process(1.0 / 60.0)
	assert_float(rig.global_position.x).is_equal_approx(10.0, 0.05)


func test_zoom_actions_change_zoom_target_within_limits() -> void:
	var rig := _make_rig(_make_target())
	rig._unhandled_input(_action(&"camera_zoom_in"))
	assert_float(rig.zoom_target()).is_equal_approx(
		_settings.zoom_default - _settings.zoom_step, EPSILON
	)
	for i in 100:
		rig._unhandled_input(_action(&"camera_zoom_out"))
	assert_float(rig.zoom_target()).is_equal(_settings.zoom_max)


func test_look_orbits_and_respects_pitch_limit() -> void:
	var rig := _make_rig(_make_target())
	rig.apply_look(Vector2(100.0, 0.0))
	assert_float(rig.yaw()).is_equal_approx(-100.0 * _settings.mouse_sensitivity, EPSILON)
	rig.apply_look(Vector2(0.0, 100000.0))
	assert_float(rig.pitch()).is_equal_approx(deg_to_rad(_settings.pitch_min_degrees), EPSILON)


func test_auto_recentre_swings_behind_moving_target_after_delay() -> void:
	var target := _make_target()
	var rig := _make_rig(target)
	target.rotation.y = 1.5
	rig.apply_look(Vector2.ZERO)  # reset the look timer
	var step := 1.0 / 60.0
	var frames := int((_settings.recentre_delay + 4.0) / step)
	for i in frames:
		target.global_position += Vector3(0.0, 0.0, -3.0 * step)  # 3 m/s
		rig._process(step)
	assert_float(rig.yaw()).is_equal_approx(1.5, 0.02)


func test_no_recentre_when_target_is_still() -> void:
	var target := _make_target()
	var rig := _make_rig(target)
	target.rotation.y = 1.5
	for i in 300:
		rig._process(1.0 / 60.0)
	assert_float(rig.yaw()).is_equal(0.0)


func test_rebase_does_not_trigger_auto_recentre() -> void:
	FloatingOrigin.reset()
	FloatingOrigin.configure(64.0, 100.0)
	var target := _make_target(Vector3(300.0, 0.0, 0.0))
	target.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	var rig := _make_rig(target)
	target.rotation.y = 1.5
	FloatingOrigin.track(target)
	for i in int((_settings.recentre_delay + 0.5) * 60.0):
		rig._process(1.0 / 60.0)  # still target: no recentre, look timer expires
	FloatingOrigin.rebase_now()
	rig._process(1.0 / 60.0)
	assert_float(rig.yaw()).is_equal(0.0)
	assert_vector(rig.global_position - target.global_position).is_equal_approx(
		Vector3(0.0, _settings.pivot_height, 0.0), Vector3.ONE * 0.05
	)
	FloatingOrigin.reset()
	GameState.chunk_size = 0.0
