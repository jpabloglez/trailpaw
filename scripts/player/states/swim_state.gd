class_name PlayerSwimState
extends PlayerState
## Floating and paddling in deep water: slower, buoyant, no jumping. Returns to land once the
## paws stand on the bottom in shallow water.


func enter(_previous: StringName) -> void:
	movement.swimming = true


func exit(_next: StringName) -> void:
	movement.swimming = false


func physics_update(delta: float) -> void:
	movement.consume_jump_request()  # no jumping while swimming
	movement.apply_swim_movement(delta)
	movement.move()
	if movement.should_stop_swimming():
		machine.transition_to(LOCOMOTION if movement.has_move_input() else IDLE)
