class_name PlayerInput
extends Node
## Reads the player's [InputMap] actions and writes them as intent into a
## [MovementComponent]. Runs before other physics callbacks so states see fresh input.

## Component that receives the intent.
@export var movement: MovementComponent


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	if movement == null:
		return
	movement.move_input = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	movement.sprint = Input.is_action_pressed(&"sprint")
	if Input.is_action_just_pressed(&"jump"):
		movement.request_jump()
