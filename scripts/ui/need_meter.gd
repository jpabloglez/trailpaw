class_name NeedMeter
extends Control
## One HUD meter: a code-drawn icon ([NeedIcon]) inside a ring that empties with the need.
##
## Full meters fade out after [member NeedsHudSettings.full_hold]; a meter reappears as soon as
## its need drops below [member NeedsHudSettings.full_fraction]. A critical meter pulses
## gently (it dims and brightens; no red, no sound — ADR-003).
## [br][br]
## Budget: redraws only when its value, opacity or pulse changes.

## The need shown.
var definition: NeedDefinition
## Look and timing.
var settings: NeedsHudSettings

var _fraction: float = 1.0
var _critical: bool = false
var _full_for: float = 0.0
var _pulse_time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * settings.meter_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_for = settings.full_hold  # starts full: hidden from the first frame
	modulate.a = 0.0


func _process(delta: float) -> void:
	advance(delta)


## Shows [param value] of the need and whether it is critical.
func set_value(value: float, critical: bool) -> void:
	_fraction = clampf(value / definition.max_value, 0.0, 1.0)
	if critical != _critical:
		_critical = critical
		_pulse_time = 0.0
	queue_redraw()


## Advances fading and pulsing by [param delta] seconds.
func advance(delta: float) -> void:
	var full := _fraction >= settings.full_fraction
	_full_for = _full_for + delta if full else 0.0
	var target := 0.0 if full and _full_for >= settings.full_hold else 1.0
	var alpha := move_toward(modulate.a, target, settings.fade_per_second * delta)
	if alpha != modulate.a:
		modulate.a = alpha
	if _critical:
		_pulse_time += delta
		queue_redraw()


## Shown fraction of the need (0…1), i.e. how much of the ring is filled.
func fraction() -> float:
	return _fraction


## Current opacity (0 = faded out).
func opacity() -> float:
	return modulate.a


## Current pulse dimming (0 = none; up to [member NeedsHudSettings.pulse_amount]).
func pulse() -> float:
	if not _critical:
		return 0.0
	return settings.pulse_amount * 0.5 * (1.0 - cos(TAU * settings.pulse_hz * _pulse_time))


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - settings.ring_width * 0.5
	var brightness := 1.0 - pulse()
	var fill := definition.color * Color(brightness, brightness, brightness, 1.0)
	draw_circle(center, radius, settings.backdrop_color)
	draw_arc(center, radius, 0.0, TAU, 48, settings.backdrop_color, settings.ring_width, true)
	if _fraction > 0.0:
		var start := -PI * 0.5
		draw_arc(
			center, radius, start, start + TAU * _fraction, 48, fill, settings.ring_width, true
		)
	var icon := settings.icon_color * Color(brightness, brightness, brightness, 1.0)
	NeedIcon.draw(self, definition.icon_shape, center, radius * 0.62, icon)
