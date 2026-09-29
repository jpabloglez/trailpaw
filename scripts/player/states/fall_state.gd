class_name PlayerFallState
extends PlayerState
## Airborne and descending (after a jump apex or walking off a ledge). Lands on floor.


func physics_update(delta: float) -> void:
	movement.apply_air_movement(delta)
	movement.apply_gravity(delta)
	movement.move()
	if movement.should_start_swimming():
		machine.transition_to(SWIM)
		return
	if not movement.is_grounded():
		return
	if movement.has_move_input() or movement.horizontal_speed() >= LocomotionModel.IDLE_SPEED:
		machine.transition_to(LOCOMOTION)
	else:
		machine.transition_to(IDLE)
