class_name PlayerJumpState
extends PlayerState
## Rising part of a jump. The impulse is applied on enter; hands over to Fall at the apex.


func enter(_previous: StringName) -> void:
	movement.perform_jump()


func physics_update(delta: float) -> void:
	movement.apply_air_movement(delta)
	movement.apply_gravity(delta)
	movement.move()
	if movement.vertical_speed() <= 0.0:
		machine.transition_to(FALL)
