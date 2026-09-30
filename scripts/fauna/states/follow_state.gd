class_name FaunaFollowState
extends FaunaState
## Following the player for [member duration] seconds, keeping
## [member FaunaProfile.follow_distance]: trots to catch up, walks when close, waits when there.

## Seconds of following (set by [method FaunaBrain.start_follow]).
@export_range(0.0, 600.0, 1.0, "suffix:s") var duration: float = 60.0
## Beyond this distance it trots to catch up (m).
@export_range(1.0, 50.0, 0.5, "suffix:m") var trot_distance: float = 6.0

var _left: float = 0.0


func enter(_previous: StringName) -> void:
	_left = duration


func is_done() -> bool:
	return _left <= 0.0


## Seconds of following left.
func time_left() -> float:
	return _left


func physics_update(delta: float) -> void:
	_left -= delta
	var brain := agent().brain
	var distance := brain.perception.player_distance
	var keep := brain.profile.follow_distance
	if distance <= keep:
		stand()
	else:
		var pace := 1.0 if distance > trot_distance else 0.4
		steer_towards(brain.perception.player_position, pace)
	ground_tick(delta)
