class_name FaunaFleeState
extends FaunaState
## Running away from the player (the brain keeps it here until
## [member FaunaProfile.safe_distance]).


func exit(_next: StringName) -> void:
	movement.sprint = false


func physics_update(delta: float) -> void:
	var away := -agent().brain.perception.to_player if agent().brain != null else Vector3.ZERO
	if away == Vector3.ZERO:
		away = -agent().global_basis.z
	movement.sprint = true
	steer_along(away, 1.0)
	ground_tick(delta)
