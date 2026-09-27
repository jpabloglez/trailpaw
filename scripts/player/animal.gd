class_name Animal
extends CharacterBody3D
## The player-controlled animal: a [CharacterBody3D] composed of a [MovementComponent],
## [PlayerInput] and a [StateMachine] with Idle/Locomotion/Jump/Fall states.
##
## Phase 1 uses a box placeholder with a contrasting "nose" marking forward (-Z).

## Group used by tools such as the debug overlay to find the player without node paths.
const PLAYER_GROUP: StringName = &"player"

@onready var movement: MovementComponent = %MovementComponent
@onready var state_machine: StateMachine = %StateMachine


func _ready() -> void:
	add_to_group(PLAYER_GROUP)


## Snapshot for debug tools: speed (m/s), gait, state, position and grounded flag.
func get_debug_info() -> Dictionary:
	return {
		"speed": movement.horizontal_speed(),
		"gait": LocomotionModel.Gait.keys()[movement.gait()],
		"state": state_machine.current_state_name(),
		"position": global_position,
		"grounded": is_on_floor(),
	}
