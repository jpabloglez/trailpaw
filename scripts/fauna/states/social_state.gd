class_name FaunaSocialState
extends FaunaState
## Being greeted: the animal stops and sniffs back while the player greets it, for [member hold]
## seconds (a little longer than the greeting itself).

## Seconds the moment lasts.
@export_range(0.1, 30.0, 0.1, "suffix:s") var hold: float = 2.5

var _left: float = 0.0


func enter(_previous: StringName) -> void:
	_left = hold
	if agent().animation != null and agent().animation.tree() != null:
		agent().animation.play_action(&"sniff")


func is_done() -> bool:
	return _left <= 0.0


func physics_update(delta: float) -> void:
	_left -= delta
	stand()
	ground_tick(delta)
