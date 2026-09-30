class_name FaunaRestState
extends FaunaState
## Lying down for a while (profile [member FaunaProfile.rest_time]); the animation controller
## maps the state name "Rest" to its resting pose.

var _left: float = 0.0


func enter(_previous: StringName) -> void:
	var range_s := agent().brain.profile.rest_time if agent().brain != null else Vector2(10, 10)
	_left = agent().rng.randf_range(range_s.x, range_s.y)


func is_done() -> bool:
	return _left <= 0.0


func physics_update(delta: float) -> void:
	_left -= delta
	stand()
	ground_tick(delta)
