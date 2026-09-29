class_name PlayerInput
extends Node
## Reads the player's [InputMap] actions and writes them as intent into a
## [MovementComponent] and an [Interactor]. Runs before other physics callbacks so states see
## fresh input.

## Component that receives the intent.
@export var movement: MovementComponent
## Receives the interact intent (optional).
@export var interactor: Interactor


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
	if interactor != null:
		interactor.interact_held = Input.is_action_pressed(&"interact")
		if Input.is_action_just_pressed(&"interact"):
			interactor.request_interaction()
