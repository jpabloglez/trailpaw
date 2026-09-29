class_name PlayerState
extends State
## Base class for the player's locomotion states. Holds the [MovementComponent] they drive.
##
## State names used for transitions match the node names in [code]animal.tscn[/code].

const IDLE: StringName = &"Idle"
const LOCOMOTION: StringName = &"Locomotion"
const JUMP: StringName = &"Jump"
const FALL: StringName = &"Fall"
const SWIM: StringName = &"Swim"

## Component this state drives. Assigned in the scene (or by tests).
@export var movement: MovementComponent
