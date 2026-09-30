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
@onready var model_root: Node3D = %Model


func _ready() -> void:
	add_to_group(PLAYER_GROUP)
	_spawn_model()
	add_to_group(FloatingOrigin.SHIFTABLE_GROUP)


## Snapshot for debug tools: speed (m/s), gait, state, position and grounded flag.
func get_debug_info() -> Dictionary:
	return {
		"speed": movement.horizontal_speed(),
		"gait": LocomotionModel.Gait.keys()[movement.gait()],
		"state": state_machine.current_state_name(),
		"position": global_position,
		"grounded": is_on_floor(),
	}


## Instances the species model under [member model_root] and hides the placeholder box. A
## species without a model keeps the Phase 1 placeholder.
func _spawn_model() -> void:
	if not spawn_species_model(movement.species, model_root):
		return
	for placeholder: String in ["Body", "Nose"]:
		(get_node(placeholder) as Node3D).visible = false
	(%AnimationController as AnimationController).initialize()


## Instances [param species]' model under [param root] (scaled and turned to face −Z).
## Returns [code]false[/code] when the species has no model. Shared with fauna.
static func spawn_species_model(species: AnimalSpecies, root: Node3D) -> bool:
	if species == null or species.model_scene == null:
		return false
	var model := species.model_scene.instantiate() as Node3D
	model.name = "Species"
	model.scale = Vector3.ONE * species.model_scale
	model.rotation.y = deg_to_rad(species.model_yaw_degrees)
	root.add_child(model)
	return true
