class_name DebugOverlay
extends CanvasLayer
## F3 debug overlay: FPS plus the player's speed, gait, state and position.
##
## Finds the player through the [constant Animal.PLAYER_GROUP] group (no node paths) and
## reads [method Animal.get_debug_info]; other systems add lines through
## [constant LINES_GROUP]. Hidden by default; toggling emits
## [code]EventBus.debug_overlay_toggled[/code].
## [br][br]
## Budget: refreshes at [constant REFRESH_HZ] Hz, not every frame, so the string building
## (the only allocation) happens ten times per second at most; nothing runs while hidden.

## Group of nodes that add lines via [code]get_debug_lines() -> PackedStringArray[/code].
const LINES_GROUP: StringName = &"debug_lines"
## Text refreshes per second while visible.
const REFRESH_HZ: float = 10.0

var _since_refresh: float = 0.0

@onready var _label: Label = %Label


func _ready() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug_overlay"):
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_since_refresh += delta
	if _since_refresh >= 1.0 / REFRESH_HZ:
		_since_refresh = 0.0
		refresh()


## Shows or hides the overlay; refreshes immediately when shown.
func toggle() -> void:
	visible = not visible
	EventBus.debug_overlay_toggled.emit(visible)
	if visible:
		refresh()


## Rebuilds the overlay text from the current FPS and player info.
func refresh() -> void:
	var text := format_info(Engine.get_frames_per_second(), _player_info())
	for provider: Node in get_tree().get_nodes_in_group(LINES_GROUP):
		if provider.has_method(&"get_debug_lines"):
			text += "\n" + "\n".join(provider.get_debug_lines())
	_label.text = text


## Current overlay text (for tests and tools).
func text() -> String:
	return _label.text


## Formats the overlay text. [param info] is [method Animal.get_debug_info] output, or
## empty when there is no player.
static func format_info(fps: float, info: Dictionary) -> String:
	var lines := PackedStringArray(["FPS %d" % roundi(fps)])
	if info.is_empty():
		lines.append("no player")
		return "\n".join(lines)
	var pos: Vector3 = info.get("position", Vector3.ZERO)
	lines.append("speed %.2f m/s  (%s)" % [info.get("speed", 0.0), info.get("gait", "?")])
	lines.append("state %s%s" % [info.get("state", "?"), "" if info.get("grounded") else "  (air)"])
	lines.append("pos %.1f, %.1f, %.1f" % [pos.x, pos.y, pos.z])
	return "\n".join(lines)


func _player_info() -> Dictionary:
	var player := get_tree().get_first_node_in_group(Animal.PLAYER_GROUP)
	if player != null and player.has_method(&"get_debug_info"):
		return player.get_debug_info()
	return {}
