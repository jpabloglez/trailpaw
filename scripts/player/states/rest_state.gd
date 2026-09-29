class_name PlayerRestState
extends PlayerState
## Lying down to rest: the animal stops, recovers energy at the [Rester]'s rate for where it is
## (open, shade, den) and the game clock runs [member ClockSettings.rest_scale] times faster.
## It gets up when the rest (or interact, at a den) action is released or on move input.

## Seconds between place checks (open / shade / den).
const PLACE_INTERVAL: float = 0.25

## Rest rules and place.
@export var rester: Rester
## Needs recovered.
@export var needs: NeedsComponent
## Holds the interact flag (resting at a den with E).
@export var interactor: Interactor

var _place: Rester.Place = Rester.Place.OPEN
var _since_place: float = 0.0
var _active: bool = false


func enter(_previous: StringName) -> void:
	_active = true
	_since_place = 0.0
	_place = rester.place()
	GameState.clock_scale = GameState.CLOCK.rest_scale


func exit(_next: StringName) -> void:
	_active = false
	GameState.clock_scale = 1.0


func _exit_tree() -> void:
	if _active:  # freed while resting: never leave the clock fast
		GameState.clock_scale = 1.0


func physics_update(delta: float) -> void:
	movement.consume_jump_request()
	movement.apply_ground_movement(delta)
	movement.apply_gravity(delta)
	movement.move()
	var held := rester.rest_held or (interactor != null and interactor.interact_held)
	if movement.has_move_input() or not held:
		machine.transition_to(LOCOMOTION if movement.has_move_input() else IDLE)
		return
	_since_place += delta
	if _since_place >= PLACE_INTERVAL:
		_since_place = 0.0
		_place = rester.place()
	if needs != null:
		needs.add(&"energy", rester.energy_rate(_place) * delta)


## Where the animal is resting (as last checked).
func place() -> Rester.Place:
	return _place
