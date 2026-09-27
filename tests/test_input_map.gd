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
}

## Expected default mouse-button bindings.
const MOUSE_ACTIONS: Dictionary = {
	&"interact": MOUSE_BUTTON_LEFT,
	&"camera_zoom_in": MOUSE_BUTTON_WHEEL_UP,
	&"camera_zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
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
