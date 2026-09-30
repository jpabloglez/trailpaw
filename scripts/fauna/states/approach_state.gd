class_name FaunaApproachState
extends FaunaState
## Walking over to look at the player, stopping at [member FaunaProfile.approach_stop_distance],
## then watching for [member FaunaProfile.watch_time].

## Walking pace while approaching.
@export_range(0.05, 1.0, 0.01) var pace: float = 0.35

var _watch_left: float = 0.0
var _arrived: bool = false


func enter(_previous: StringName) -> void:
	_arrived = false
	_watch_left = agent().brain.profile.watch_time


func is_done() -> bool:
	return _arrived and _watch_left <= 0.0


func physics_update(delta: float) -> void:
	var brain := agent().brain
	var stop := brain.profile.approach_stop_distance
	if _arrived or brain.perception.player_distance <= stop:
		_arrived = true
		_watch_left -= delta
		stand()
	else:
		steer_towards(brain.perception.player_position, pace)
	ground_tick(delta)
