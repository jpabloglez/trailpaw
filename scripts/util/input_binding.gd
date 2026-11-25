class_name InputBinding
extends RefCounted
## Helpers for player-facing input bindings: which kind of device an [InputEvent] comes from,
## its short name ("W", "Left Click", "A", "RT") and a clean copy of it to store in the
## [InputMap]. Used by the [code]Settings[/code] autoload and the interface.

## Gamepad button names shown to the player (Xbox layout; Godot's SDL mapping puts every
## pad's face buttons in these positions).
const GAMEPAD_BUTTON_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}


## Human-readable binding of [param action]: its keyboard/mouse inputs (e.g. "W", "Wheel Up")
## or, with [param gamepad], its gamepad ones (e.g. "A", "RT"; Xbox names).
static func action_text(action: StringName, gamepad: bool = false) -> String:
	var parts := PackedStringArray()
	for event in InputMap.action_get_events(action):
		if InputBinding.is_gamepad(event) != gamepad:
			continue
		var text := InputBinding.display_name(event)
		if text != "":
			parts.append(text)
	return ", ".join(parts)


## Whether [param event] comes from a gamepad (button or stick/trigger axis).
static func is_gamepad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## Short name of a single input: a key, mouse button, gamepad button or axis direction.
static func display_name(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		return OS.get_keycode_string(key.physical_keycode)
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return _mouse_name(mouse.button_index)
	var button := event as InputEventJoypadButton
	if button != null:
		return GAMEPAD_BUTTON_NAMES.get(button.button_index, "Button %d" % button.button_index)
	var motion := event as InputEventJoypadMotion
	if motion != null:
		return _axis_name(motion.axis, motion.axis_value)
	return ""


## A clean copy of [param event] for binding (physical key, mouse button, gamepad button, or a
## gamepad axis pushed past half way, stored as its direction), or null.
static func normalise(event: InputEvent) -> InputEvent:
	var key := event as InputEventKey
	if key != null:
		var copy := InputEventKey.new()
		copy.physical_keycode = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return copy if copy.physical_keycode != 0 else null
	var mouse := event as InputEventMouseButton
	if mouse != null:
		var copy := InputEventMouseButton.new()
		copy.button_index = mouse.button_index
		return copy
	var button := event as InputEventJoypadButton
	if button != null:
		return gamepad_button(button.button_index)
	var motion := event as InputEventJoypadMotion
	if motion != null and absf(motion.axis_value) >= 0.5:
		return gamepad_axis(motion.axis, signf(motion.axis_value))
	return null


## A gamepad button event that matches every pad.
static func gamepad_button(index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = index as JoyButton
	return event


## A gamepad axis direction ([param direction] ±1) that matches every pad.
static func gamepad_axis(axis: int, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis as JoyAxis
	event.axis_value = direction
	return event


static func _axis_name(axis: JoyAxis, value: float) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		JOY_AXIS_LEFT_X:
			return "Left Stick " + ("Right" if value > 0.0 else "Left")
		JOY_AXIS_LEFT_Y:
			return "Left Stick " + ("Down" if value > 0.0 else "Up")
		JOY_AXIS_RIGHT_X:
			return "Right Stick " + ("Right" if value > 0.0 else "Left")
		JOY_AXIS_RIGHT_Y:
			return "Right Stick " + ("Down" if value > 0.0 else "Up")
	return "Axis %d" % axis


static func _mouse_name(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "Left Click"
		MOUSE_BUTTON_RIGHT:
			return "Right Click"
		MOUSE_BUTTON_MIDDLE:
			return "Middle Click"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
	return "Mouse %d" % button
