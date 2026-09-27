class_name State
extends Node
## Base class for one state of a [StateMachine].
##
## Subclasses override the virtual methods below. A state requests a change with
## [code]machine.transition_to(&"OtherState")[/code]; the node name is the state name.

## The machine that owns this state. Set by [StateMachine] before [method enter] runs.
var machine: StateMachine
## The node this machine drives (e.g. the [CharacterBody3D]). Set by [StateMachine].
var actor: Node


## Called when the machine switches to this state. [param previous] is empty on start.
func enter(_previous: StringName) -> void:
	pass


## Called when the machine leaves this state for [param next].
func exit(_next: StringName) -> void:
	pass


## Called every physics tick while this state is active.
func physics_update(_delta: float) -> void:
	pass


## Called for unhandled input events while this state is active.
func handle_input(_event: InputEvent) -> void:
	pass
