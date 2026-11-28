class_name SprintBursts
extends RefCounted
## Pure timer for limited sprinting (ADR-012): with [constant NeedEffect.Sprint.BURSTS] a
## sprint lasts [member NeedEffectTable.burst_seconds], then the animal must catch its breath
## for [member NeedEffectTable.burst_rest_seconds] before the next one. Not sprinting refills
## the burst at the same pace. [constant NeedEffect.Sprint.FULL] always allows sprinting and
## [constant NeedEffect.Sprint.NONE] never does.
## [br][br]
## Budget: a few float ops per [method step]; no allocations.

var _burst: float
var _rest: float
var _run_left: float
var _rest_left: float = 0.0


func _init(burst_seconds: float, rest_seconds: float) -> void:
	_burst = burst_seconds
	_rest = rest_seconds
	_run_left = burst_seconds


## Advances [param delta] seconds under [param limit] while the animal [param sprinting] (asks
## to run while moving). Returns whether it may sprint now.
func step(delta: float, limit: NeedEffect.Sprint, sprinting: bool) -> bool:
	match limit:
		NeedEffect.Sprint.FULL:
			_run_left = _burst
			_rest_left = 0.0
			return true
		NeedEffect.Sprint.NONE:
			return false
	if _rest_left > 0.0:
		_rest_left = maxf(_rest_left - delta, 0.0)
		if _rest_left == 0.0:
			_run_left = _burst
		return false
	if sprinting:
		_run_left -= delta
		if _run_left <= 0.0:
			_run_left = 0.0
			_rest_left = _rest
			return false
	else:
		_run_left = minf(_run_left + delta * _burst / _rest, _burst)
	return true


## Whether the animal is catching its breath after a burst.
func is_resting() -> bool:
	return _rest_left > 0.0


## Seconds of sprint left in the current burst.
func seconds_left() -> float:
	return _run_left
