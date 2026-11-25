class_name StickPress
extends RefCounted
## Turns analog stick motion into single presses for menus that read actions in
## [method Node._unhandled_input]: a stick sends a motion event for every small change while
## pushed, and each one reports the action as pressed. This keeps per-action state and reports
## a press only when the stick crosses into the action; keys and buttons pass straight through.

var _held: Dictionary[StringName, bool] = {}


## Whether [param event] is a fresh press of [param action].
func pressed(event: InputEvent, action: StringName) -> bool:
	if not event is InputEventJoypadMotion:
		return event.is_action_pressed(action)
	if not event.is_action(action):
		return false
	var down := event.get_action_strength(action) >= InputMap.action_get_deadzone(action)
	var fresh: bool = down and not _held.get(action, false)
	_held[action] = down
	return fresh
