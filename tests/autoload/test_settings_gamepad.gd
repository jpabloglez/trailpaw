## Tests for gamepad bindings in [code]Settings[/code]: names, rebinding that keeps the other
## kind of input, conflicts, persistence (including files written before gamepad support) and
## the right-stick sensitivity.
extends GdUnitTestSuite

const TEST_PATH: String = "user://test_settings_gamepad.cfg"

var _saved_path: String


func before_test() -> void:
	_saved_path = Settings.config_path
	Settings.config_path = TEST_PATH


func after_test() -> void:
	Settings.restore_default_bindings()
	Settings.set_stick_sensitivity(1.0)
	Settings.config_path = _saved_path
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _pad(button: JoyButton, device: int = 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = true
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func test_binding_text_lists_one_kind_of_input() -> void:
	assert_str(InputBinding.action_text(&"jump")).is_equal("Space")
	assert_str(InputBinding.action_text(&"jump", true)).is_equal("A")
	assert_str(InputBinding.action_text(&"sprint", true)).is_equal("RT")
	assert_str(InputBinding.action_text(&"move_forward", true)).is_equal("Left Stick Up")
	assert_str(InputBinding.action_text(&"interact")).is_equal("E, Left Click")


func test_input_names() -> void:
	assert_str(InputBinding.display_name(_pad(JOY_BUTTON_RIGHT_SHOULDER))).is_equal("RB")
	assert_str(InputBinding.display_name(_pad(JOY_BUTTON_START))).is_equal("Menu")
	assert_str(InputBinding.display_name(_axis(JOY_AXIS_TRIGGER_LEFT, 1.0))).is_equal("LT")
	assert_str(InputBinding.display_name(_axis(JOY_AXIS_RIGHT_X, -1.0))).is_equal(
		"Right Stick Left"
	)


func test_rebinding_a_key_keeps_the_gamepad_button_and_back() -> void:
	assert_str(String(Settings.rebind(&"jump", _key(KEY_K)))).is_empty()
	assert_bool(InputMap.action_has_event(&"jump", _pad(JOY_BUTTON_A))).is_true()
	assert_str(String(Settings.rebind(&"jump", _pad(JOY_BUTTON_LEFT_STICK)))).is_empty()
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_K))).is_true()
	assert_bool(InputMap.action_has_event(&"jump", _pad(JOY_BUTTON_A))).is_false()
	assert_str(InputBinding.action_text(&"jump", true)).is_equal("LS")


func test_gamepad_bindings_work_on_any_pad() -> void:
	Settings.rebind(&"sniff", _pad(JOY_BUTTON_DPAD_DOWN, 2))
	assert_bool(InputMap.event_is_action(_pad(JOY_BUTTON_DPAD_DOWN, 0), &"sniff")).is_true()
	assert_bool(InputMap.event_is_action(_pad(JOY_BUTTON_DPAD_DOWN, 3), &"sniff")).is_true()


func test_a_gamepad_input_used_elsewhere_is_refused() -> void:
	assert_str(String(Settings.rebind(&"sniff", _pad(JOY_BUTTON_A)))).is_equal("jump")
	assert_str(String(Settings.rebind(&"jump", _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)))).is_equal(
		"sprint"
	)
	assert_bool(InputMap.action_has_event(&"sniff", _pad(JOY_BUTTON_Y))).is_true()


func test_a_slight_axis_push_cannot_be_bound() -> void:
	assert_str(String(Settings.rebind(&"rest", _axis(JOY_AXIS_TRIGGER_LEFT, 0.2)))).is_equal("?")
	assert_str(String(Settings.rebind(&"rest", _axis(JOY_AXIS_TRIGGER_LEFT, 0.8)))).is_empty()
	assert_str(InputBinding.action_text(&"rest", true)).is_equal("LT")


func test_gamepad_bindings_and_stick_sensitivity_persist() -> void:
	Settings.rebind(&"map", _pad(JOY_BUTTON_DPAD_UP))
	Settings.rebind(&"rest", _axis(JOY_AXIS_TRIGGER_LEFT, 1.0))
	Settings.set_stick_sensitivity(2.5)
	assert_int(Settings.save_settings()).is_equal(OK)
	Settings.restore_default_bindings()
	Settings.set_stick_sensitivity(1.0)
	Settings.load_settings()
	assert_str(InputBinding.action_text(&"map", true)).is_equal("D-pad Up")
	assert_str(InputBinding.action_text(&"map")).is_equal("M")
	assert_str(InputBinding.action_text(&"rest", true)).is_equal("LT")
	assert_float(Settings.stick_sensitivity).is_equal_approx(2.5, 1e-4)


func test_a_file_from_before_gamepad_support_keeps_the_default_pad_bindings() -> void:
	var config := ConfigFile.new()
	config.set_value("bindings", "jump", [{"key": KEY_K}])
	assert_int(config.save(TEST_PATH)).is_equal(OK)
	Settings.load_settings()
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_K))).is_true()
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_SPACE))).is_false()
	assert_bool(InputMap.action_has_event(&"jump", _pad(JOY_BUTTON_A))).is_true()


func test_stick_sensitivity_is_clamped() -> void:
	Settings.set_stick_sensitivity(9.0)
	assert_float(Settings.stick_sensitivity).is_equal(3.0)
	Settings.set_stick_sensitivity(0.0)
	assert_float(Settings.stick_sensitivity).is_equal(0.2)
