## Tests for persistent settings: values and key bindings survive a save and a load, rebinding
## refuses keys used elsewhere, defaults can be restored, and the camera follows the settings.
extends GdUnitTestSuite

const TEST_PATH: String = "user://test_settings.cfg"
const RIG_SCENE: String = "res://scenes/player/camera_rig.tscn"

var _saved_path: String


func before_test() -> void:
	_saved_path = Settings.config_path
	Settings.config_path = TEST_PATH


func after_test() -> void:
	Settings.restore_default_bindings()
	Settings.set_quality(load(Settings.DEFAULT_QUALITY_PATH))
	Settings.set_fov(70.0)
	Settings.set_mouse_sensitivity(1.0)
	Settings.set_invert_y(false)
	Settings.set_render_scale(1.0)
	Settings.set_volume(&"Ambience", 1.0)
	Settings.set_camera_shake(true)
	Settings.set_sprint_toggle(false)
	Settings.set_rest_toggle(false)
	Settings.set_ui_scale(1.0)
	Settings.config_path = _saved_path
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func test_settings_persist_across_a_save_and_a_load() -> void:
	Settings.set_quality(load("res://data/quality/low.tres"))
	Settings.set_fov(85.0)
	Settings.set_mouse_sensitivity(1.5)
	Settings.set_invert_y(true)
	Settings.set_render_scale(0.75)
	Settings.set_volume(&"Ambience", 0.3)
	Settings.set_camera_shake(false)
	Settings.set_sprint_toggle(true)
	Settings.set_rest_toggle(true)
	Settings.set_ui_scale(1.3)
	assert_str(String(Settings.rebind(&"jump", _key(KEY_J)))).is_empty()
	assert_int(Settings.save_settings()).is_equal(OK)
	# Forget everything, then read it back.
	Settings.set_quality(load("res://data/quality/high.tres"))
	Settings.set_fov(70.0)
	Settings.set_mouse_sensitivity(1.0)
	Settings.set_invert_y(false)
	Settings.set_render_scale(1.0)
	Settings.set_volume(&"Ambience", 1.0)
	Settings.set_camera_shake(true)
	Settings.set_sprint_toggle(false)
	Settings.set_rest_toggle(false)
	Settings.set_ui_scale(1.0)
	Settings.restore_default_bindings()
	Settings.load_settings()
	assert_str(String(Settings.quality.id)).is_equal("low")
	assert_float(Settings.fov).is_equal(85.0)
	assert_float(Settings.mouse_sensitivity).is_equal(1.5)
	assert_bool(Settings.invert_y).is_true()
	assert_float(Settings.render_scale).is_equal(0.75)
	assert_float(Settings.volume(&"Ambience")).is_equal_approx(0.3, 1e-4)
	assert_bool(Settings.camera_shake).is_false()
	assert_bool(Settings.sprint_toggle).is_true()
	assert_bool(Settings.rest_toggle).is_true()
	assert_float(Settings.ui_scale).is_equal_approx(1.3, 1e-4)
	assert_float(get_tree().root.content_scale_factor).is_equal_approx(1.3, 1e-4)
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_J))).is_true()
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_SPACE))).is_false()


func test_a_missing_or_broken_file_keeps_the_defaults() -> void:
	Settings.load_settings()  # no file yet
	assert_float(Settings.fov).is_equal(70.0)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string('[graphics]\nfov="not a number"\nquality="ultra"\n')
	file.close()
	Settings.load_settings()
	assert_float(Settings.fov).is_between(50.0, 100.0)
	assert_str(String(Settings.quality.id)).is_equal("medium")


func test_rebinding_refuses_a_key_used_by_another_action() -> void:
	assert_str(String(Settings.rebind(&"sprint", _key(KEY_W)))).is_equal("move_forward")
	assert_bool(InputMap.action_has_event(&"sprint", _key(KEY_SHIFT))).is_true()  # unchanged
	assert_bool(InputMap.action_has_event(&"move_forward", _key(KEY_W))).is_true()


func test_rebinding_to_a_mouse_button_and_its_name() -> void:
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	assert_str(String(Settings.rebind(&"sniff", middle))).is_empty()
	assert_str(Settings.binding_text(&"sniff")).is_equal("Middle Click")


func test_debug_actions_cannot_be_rebound() -> void:
	assert_str(String(Settings.rebind(&"toggle_debug_overlay", _key(KEY_F9)))).is_equal("?")


func test_restore_defaults_brings_back_the_project_bindings() -> void:
	Settings.rebind(&"jump", _key(KEY_J))
	Settings.restore_default_bindings()
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_SPACE))).is_true()
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_J))).is_false()


func test_the_camera_follows_fov_sensitivity_and_invert_y() -> void:
	var rig: CameraRig = auto_free(load(RIG_SCENE).instantiate())
	add_child(rig)
	Settings.set_fov(80.0)
	assert_float(rig.camera.fov).is_equal(80.0)
	var yaw := rig.get_node("%Yaw") as Node3D
	var before := yaw.rotation.y
	rig.apply_look(Vector2(10, 0))
	var normal_turn := absf(yaw.rotation.y - before)
	Settings.set_mouse_sensitivity(2.0)
	before = yaw.rotation.y
	rig.apply_look(Vector2(10, 0))
	assert_float(absf(yaw.rotation.y - before)).is_equal_approx(normal_turn * 2.0, 1e-5)
	var pitch := rig.get_node("%Pitch") as Node3D
	Settings.set_mouse_sensitivity(1.0)
	var p0 := pitch.rotation.x
	rig.apply_look(Vector2(0, 5))
	var down := pitch.rotation.x - p0
	Settings.set_invert_y(true)
	p0 = pitch.rotation.x
	rig.apply_look(Vector2(0, 5))
	assert_float(signf(pitch.rotation.x - p0)).is_equal(-signf(down))


func test_text_size_scales_the_whole_interface_within_limits() -> void:
	Settings.set_ui_scale(1.2)
	assert_float(get_tree().root.content_scale_factor).is_equal_approx(1.2, 1e-4)
	Settings.set_ui_scale(3.0)
	assert_float(Settings.ui_scale).is_equal_approx(1.5, 1e-4)
	Settings.set_ui_scale(1.23)
	assert_float(Settings.ui_scale).is_equal_approx(1.2, 1e-4)  # steps of 10 %


func test_the_interface_tab_and_hold_or_toggle_choices() -> void:
	var menu: SettingsMenu = auto_free(SettingsMenu.new())
	add_child(menu)
	menu.open()
	var size := menu.control("TextSize") as OptionButton
	size.select(3)
	size.item_selected.emit(3)
	assert_float(Settings.ui_scale).is_equal_approx(1.3, 1e-4)
	var sprint := menu.control("SprintMode") as OptionButton
	sprint.select(1)
	sprint.item_selected.emit(1)
	assert_bool(Settings.sprint_toggle).is_true()
	menu.visible = false
