## Which kind of device the player is using right now — keyboard and mouse or a gamepad — so
## prompts and hints name the right inputs ("E" or "X"). Switches on the first deliberate input
## from the other kind: a key, a mouse click or a real mouse move, a pad button or a stick or
## trigger pushed past half way (so a resting stick or a nudged mouse does not flip it).
## [br][br]
## Autoload name: [code]InputDevice[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
## [br][br]
## Budget: a type check per input event; nothing per frame.
extends Node

## The player switched between keyboard/mouse and gamepad.
signal changed(gamepad: bool)

## Mouse movement (pixels in one event) that counts as using the mouse.
const MOUSE_MOVE_THRESHOLD: float = 4.0
## Stick or trigger push that counts as using the pad.
const AXIS_THRESHOLD: float = 0.5

## Whether the last deliberate input came from a gamepad.
var using_gamepad: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	observe(event)


## Updates [member using_gamepad] from [param event] (called for every input event).
func observe(event: InputEvent) -> void:
	var gamepad := using_gamepad
	if event is InputEventJoypadButton:
		gamepad = gamepad or (event as InputEventJoypadButton).pressed
	elif event is InputEventJoypadMotion:
		gamepad = gamepad or absf((event as InputEventJoypadMotion).axis_value) >= AXIS_THRESHOLD
	elif event is InputEventKey or event is InputEventMouseButton:
		gamepad = gamepad and not event.is_pressed()
	elif event is InputEventMouseMotion:
		var moved := (event as InputEventMouseMotion).relative.length() >= MOUSE_MOVE_THRESHOLD
		gamepad = gamepad and not moved
	set_gamepad(gamepad)


## Sets which device is in use, notifying [signal changed] when it changes.
func set_gamepad(value: bool) -> void:
	if value == using_gamepad:
		return
	using_gamepad = value
	changed.emit(value)


## The player-facing binding of [param action] for the device in use (e.g. "E" or "X"),
## falling back to the other kind when the action has none on this one.
func action_text(action: StringName) -> String:
	var text := InputBinding.action_text(action, using_gamepad)
	return text if text != "" else InputBinding.action_text(action, not using_gamepad)
