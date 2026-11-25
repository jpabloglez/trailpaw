## Tests for [code]InputDevice[/code]: it follows the last deliberate input, ignores a resting
## stick or a nudged mouse, and prompts and hints name the inputs of the device in use.
extends GdUnitTestSuite

var _changes: Array[bool] = []


func before_test() -> void:
	InputDevice.set_gamepad(false)
	_changes.clear()
	InputDevice.changed.connect(_on_changed)


func after_test() -> void:
	InputDevice.changed.disconnect(_on_changed)
	InputDevice.set_gamepad(false)


func _on_changed(gamepad: bool) -> void:
	_changes.append(gamepad)


func _pad_button(pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = pressed
	return event


func _axis(value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	return event


func _mouse_move(pixels: float) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(pixels, 0.0)
	return event


func _key() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	return event


func test_a_pad_button_or_a_real_push_switches_to_the_gamepad() -> void:
	InputDevice.observe(_axis(0.2))  # a resting stick drifts
	assert_bool(InputDevice.using_gamepad).is_false()
	InputDevice.observe(_axis(0.8))
	assert_bool(InputDevice.using_gamepad).is_true()
	InputDevice.set_gamepad(false)
	InputDevice.observe(_pad_button(false))  # a release alone says nothing
	assert_bool(InputDevice.using_gamepad).is_false()
	InputDevice.observe(_pad_button())
	assert_bool(InputDevice.using_gamepad).is_true()
	assert_array(_changes).is_equal([true, false, true])


func test_a_key_or_a_real_mouse_move_switches_back() -> void:
	InputDevice.observe(_pad_button())
	InputDevice.observe(_mouse_move(1.0))  # a nudged desk
	assert_bool(InputDevice.using_gamepad).is_true()
	InputDevice.observe(_mouse_move(20.0))
	assert_bool(InputDevice.using_gamepad).is_false()
	InputDevice.observe(_pad_button())
	InputDevice.observe(_key())
	assert_bool(InputDevice.using_gamepad).is_false()


func test_action_text_follows_the_device() -> void:
	assert_str(InputDevice.action_text(&"jump")).is_equal("Space")
	assert_str(InteractionPrompt.interact_key()).is_equal("E")
	assert_str(HintDirector.move_text()).is_equal("WASD")
	InputDevice.set_gamepad(true)
	assert_str(InputDevice.action_text(&"jump")).is_equal("A")
	assert_str(InteractionPrompt.interact_key()).is_equal("X")
	assert_str(HintDirector.move_text()).is_equal("Left Stick")
	# An action without pad inputs falls back to the keyboard's.
	assert_str(InputDevice.action_text(&"toggle_debug_overlay")).is_equal("F3")
