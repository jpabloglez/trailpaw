class_name PlayerIdleState
extends PlayerState
## Standing still on the ground. Decelerates to rest; leaves on input, jump or losing floor.


func physics_update(delta: float) -> void:
	if movement.is_grounded() and movement.consume_jump_request():
		machine.transition_to(JUMP)
		return
	movement.apply_ground_movement(delta)
	movement.apply_gravity(delta)
	movement.move()
	if movement.should_start_swimming():
		machine.transition_to(SWIM)
		return
	if not movement.is_grounded():
		machine.transition_to(FALL)
	elif movement.has_move_input():
		machine.transition_to(LOCOMOTION)
