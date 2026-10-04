class_name PlayerInput
extends Node
## Reads the player's [InputMap] actions and writes them as intent into a
## [MovementComponent] and an [Interactor]. Runs before other physics callbacks so states see
## fresh input.

## Component that receives the intent.
@export var movement: MovementComponent
## Receives the interact intent (optional).
@export var interactor: Interactor
## Receives the rest intent (optional).
@export var rester: Rester
## Receives the sniff intent (optional).
@export var sniffer: Sniffer

var _sprint_on: bool = false
var _rest_on: bool = false


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	if movement == null:
		return
	movement.move_input = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	movement.sprint = sprint_intent(
		Input.is_action_pressed(&"sprint"), Input.is_action_just_pressed(&"sprint")
	)
	if Input.is_action_just_pressed(&"jump"):
		movement.request_jump()
	if sniffer != null and Input.is_action_just_pressed(&"sniff"):
		sniffer.request_sniff()
	if rester != null:
		rester.rest_held = rest_intent(
			Input.is_action_pressed(&"rest"), Input.is_action_just_pressed(&"rest")
		)
	if interactor != null:
		interactor.interact_held = Input.is_action_pressed(&"interact")
		if Input.is_action_just_pressed(&"interact"):
			interactor.request_interaction()


## Whether to run, from the sprint key: [param held] in hold mode; in toggle mode a press
## ([param just_pressed]) flips it and stopping turns it off.
func sprint_intent(held: bool, just_pressed: bool) -> bool:
	if not Settings.sprint_toggle:
		_sprint_on = false
		return held
	_sprint_on = toggle_step(_sprint_on, just_pressed, not movement.has_move_input())
	return _sprint_on


## Whether to rest, from the rest key: [param held] in hold mode; in toggle mode a press flips it
## and moving turns it off.
func rest_intent(held: bool, just_pressed: bool) -> bool:
	if not Settings.rest_toggle:
		_rest_on = false
		return held
	_rest_on = toggle_step(_rest_on, just_pressed, movement.has_move_input())
	return _rest_on


## Toggle mode of a held action: [param pressed] flips [param on]; [param cancel] (stopping, for
## sprint; moving, for rest) turns it off.
static func toggle_step(on: bool, pressed: bool, cancel: bool) -> bool:
	if pressed:
		return not on
	return on and not cancel
