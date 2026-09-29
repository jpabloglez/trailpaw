class_name Rester
extends Node
## Lets the animal rest: while the controller holds [code]rest[/code] (R) on the ground, or
## after choosing a REST target such as a den, the [StateMachine] goes to the Rest state, which
## recovers energy at [method energy_rate] and speeds up the game clock.
##
## Where it rests matters ([enum Place]): in the open, in a tree's shade (asked to the
## [WorldStreamer] found through [constant WorldStreamer.GROUP], or to [member shade_source])
## or by a den (the [Interactor]'s current target is a REST target).
## [br][br]
## Budget: a state check per physics frame; the place is recomputed by the Rest state 4×/s.

## Where the animal rests.
enum Place { OPEN, SHADE, DEN }

## State that performs resting.
const REST_STATE: StringName = &"Rest"
## States from which resting may start.
const START_STATES: Array[StringName] = [&"Idle", &"Locomotion"]

## Recovery rates.
@export var settings: RestSettings
## The animal body.
@export var body: CharacterBody3D
## Movement (grounded, swimming, input).
@export var movement: MovementComponent
## Gameplay state machine.
@export var state_machine: StateMachine
## Provides den targets.
@export var interactor: Interactor
## Object with [code]is_shaded(global_position) -> bool[/code]; defaults to the
## [WorldStreamer] in the scene.
@export var shade_source: Node

## Whether the controller holds the rest action.
var rest_held: bool = false


func _ready() -> void:
	process_physics_priority = -5


func _physics_process(_delta: float) -> void:
	if rest_held and can_start() and not movement.has_move_input():
		state_machine.transition_to(REST_STATE)


## Whether resting can start now.
func can_start() -> bool:
	return (
		movement.is_grounded()
		and not movement.swimming
		and START_STATES.has(state_machine.current_state_name())
	)


## Where the animal is resting now.
func place() -> Place:
	var target := interactor.current_target() if interactor != null else null
	if target != null and target.definition.type == InteractionDefinition.Type.REST:
		return Place.DEN
	var shade := _shade()
	if shade != null and shade.call(&"is_shaded", body.global_position):
		return Place.SHADE
	return Place.OPEN


## Energy recovered per second resting at [param where].
func energy_rate(where: Place) -> float:
	match where:
		Place.SHADE:
			return settings.energy_per_second * settings.shade_multiplier
		Place.DEN:
			return settings.energy_per_second * settings.den_multiplier
	return settings.energy_per_second


func _shade() -> Node:
	if shade_source == null and is_inside_tree():
		shade_source = get_tree().get_first_node_in_group(WorldStreamer.GROUP)
	return shade_source
