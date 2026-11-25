## Verifies the default InputMap defined in project.godot (ARCHITECTURE §4.5).
extends GdUnitTestSuite

## Expected default key bindings (physical keycodes).
const KEY_ACTIONS: Dictionary = {
	&"move_forward": KEY_W,
	&"move_back": KEY_S,
	&"move_left": KEY_A,
	&"move_right": KEY_D,
	&"sprint": KEY_SHIFT,
	&"jump": KEY_SPACE,
	&"interact": KEY_E,
	&"sniff": KEY_Q,
	&"rest": KEY_R,
	&"pause": KEY_ESCAPE,
	&"toggle_debug_overlay": KEY_F3,
	&"toggle_free_fly": KEY_F4,
	&"debug_refill_needs": KEY_F5,
}

## Expected default mouse-button bindings.
const MOUSE_ACTIONS: Dictionary = {
	&"interact": MOUSE_BUTTON_LEFT,
	&"camera_zoom_in": MOUSE_BUTTON_WHEEL_UP,
	&"camera_zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
}

## Expected default gamepad buttons (Xbox layout).
const PAD_BUTTONS: Dictionary = {
	&"jump": JOY_BUTTON_A,
	&"rest": JOY_BUTTON_B,
	&"interact": JOY_BUTTON_X,
	&"sniff": JOY_BUTTON_Y,
	&"camera_zoom_out": JOY_BUTTON_LEFT_SHOULDER,
	&"camera_zoom_in": JOY_BUTTON_RIGHT_SHOULDER,
	&"map": JOY_BUTTON_BACK,
	&"journal": JOY_BUTTON_DPAD_LEFT,
	&"pause": JOY_BUTTON_START,
}

## Expected default gamepad axis directions: action → [axis, direction].
const PAD_AXES: Dictionary = {
	&"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"sprint": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	&"camera_look_left": [JOY_AXIS_RIGHT_X, -1.0],
	&"camera_look_right": [JOY_AXIS_RIGHT_X, 1.0],
	&"camera_look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	&"camera_look_down": [JOY_AXIS_RIGHT_Y, 1.0],
}


func test_all_actions_exist() -> void:
	for action: StringName in KEY_ACTIONS.keys() + MOUSE_ACTIONS.keys():
		var message: String = "missing action '%s'" % action
		assert_bool(InputMap.has_action(action)).override_failure_message(message).is_true()


func test_default_key_bindings() -> void:
	for action: StringName in KEY_ACTIONS:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ACTIONS[action]
		var message: String = "'%s' is not bound to %s" % [action, event.as_text()]
		var has_event: bool = InputMap.action_has_event(action, event)
		assert_bool(has_event).override_failure_message(message).is_true()


func test_default_mouse_bindings() -> void:
	for action: StringName in MOUSE_ACTIONS:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_ACTIONS[action]
		var message: String = "'%s' is not bound to %s" % [action, event.as_text()]
		var has_event: bool = InputMap.action_has_event(action, event)
		assert_bool(has_event).override_failure_message(message).is_true()


func test_default_gamepad_buttons_work_on_any_pad() -> void:
	for action: StringName in PAD_BUTTONS:
		for device in [0, 1]:
			var event := InputEventJoypadButton.new()
			event.device = device
			event.button_index = PAD_BUTTONS[action]
			event.pressed = true
			var message: String = "'%s' is not bound to %s" % [action, event.as_text()]
			var matches: bool = InputMap.event_is_action(event, action)
			assert_bool(matches).override_failure_message(message).is_true()


func test_default_gamepad_axes() -> void:
	for action: StringName in PAD_AXES:
		var event := InputEventJoypadMotion.new()
		event.axis = PAD_AXES[action][0]
		event.axis_value = PAD_AXES[action][1]
		var message: String = "'%s' is not bound to %s" % [action, event.as_text()]
		var matches: bool = InputMap.event_is_action(event, action)
		assert_bool(matches).override_failure_message(message).is_true()
