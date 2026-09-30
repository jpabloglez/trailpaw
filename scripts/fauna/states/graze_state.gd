class_name FaunaGrazeState
extends FaunaState
## Standing and grazing for a bout (profile [member FaunaProfile.graze_time]).

var _left: float = 0.0


func enter(_previous: StringName) -> void:
	var range_s := agent().brain.profile.graze_time if agent().brain != null else Vector2(5, 5)
	_left = agent().rng.randf_range(range_s.x, range_s.y)


func is_done() -> bool:
	return _left <= 0.0


func physics_update(delta: float) -> void:
	_left -= delta
	stand()
	ground_tick(delta)
	var animation := agent().animation
	if (
		animation != null
		and animation.tree() != null
		and animation.current_state() == &"locomotion"
	):
		if movement.horizontal_speed() < 0.2:
			animation.play_action(&"eat")
