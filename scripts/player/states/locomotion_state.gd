class_name PlayerLocomotionState
extends PlayerState
## Walking, trotting or running on the ground. Returns to Idle once stopped without input.


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
	elif not movement.has_move_input() and movement.horizontal_speed() < LocomotionModel.IDLE_SPEED:
		machine.transition_to(IDLE)
