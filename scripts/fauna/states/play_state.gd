class_name FaunaPlayState
extends FaunaState
## Playing: the animal gallops in circles around the player for [member duration] seconds; a
## species that follows after playing ([method FaunaSpecies.follows_after_play]) then follows.

## Seconds of play.
@export_range(0.5, 60.0, 0.5, "suffix:s") var duration: float = 5.0
## Radius of the circles around the player (m).
@export_range(1.0, 20.0, 0.5, "suffix:m") var radius: float = 3.5

var _left: float = 0.0


func enter(_previous: StringName) -> void:
	_left = duration


func is_done() -> bool:
	return _left <= 0.0


func exit(_next: StringName) -> void:
	movement.sprint = false


func physics_update(delta: float) -> void:
	_left -= delta
	var brain := agent().brain
	var centre := brain.perception.player_position
	var offset := agent().global_position - centre
	offset.y = 0.0
	if offset.length() < 0.1:
		offset = Vector3.RIGHT
	# Tangent around the player, pulled back onto the circle.
	var tangent := Vector3.UP.cross(offset.normalized())
	var pull := offset.normalized() * (radius - offset.length()) * 0.5
	movement.sprint = false
	steer_along((tangent + pull).normalized(), 1.0)
	ground_tick(delta)
	if _left <= 0.0 and agent().fauna != null and agent().fauna.follows_after_play():
		brain.start_follow(agent().fauna.follow_seconds)
