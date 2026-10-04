class_name ScreenFade
extends CanvasLayer
## A full-screen colour that fades in and out above everything (except the cursor), used by
## [GameFlow] to hide the moment one world is swapped for another. Works while paused.

## Seconds to fade to the colour and back.
const SECONDS: float = 0.3

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Cover"
	_rect.color = Color(0.03, 0.04, 0.03, 1.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)


## Fades to fully covered; await [signal Tween.finished] on the result.
func cover() -> Tween:
	return _fade(1.0)


## Fades back to clear.
func reveal() -> Tween:
	return _fade(0.0)


## How covered the screen is now (0 clear … 1 covered).
func opacity() -> float:
	return _rect.modulate.a


func _fade(to: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_rect, ^"modulate:a", to, SECONDS * absf(to - _rect.modulate.a))
	return _tween
