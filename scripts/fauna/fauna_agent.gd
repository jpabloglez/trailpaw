class_name FaunaAgent
extends CharacterBody3D
## An AI-driven animal: the same [MovementComponent], [AnimationController], [GroundAligner]
## and [StateMachine] as the player's [Animal], but its intent comes from behaviour states
## instead of input, as world directions ([member MovementComponent.camera_relative] off).
##
## Set [member species] before adding it to the tree. It lives on the [code]fauna[/code]
## physics layer (collides with the world only) and follows floating-origin rebases.
## [br][br]
## Budget: like the player — one [method CharacterBody3D.move_and_slide] per physics tick,
## ground rays and one [AnimationTree]; the fauna AI LOD (Phase 8) throttles far agents.

## Group of every fauna agent.
const GROUP: StringName = &"fauna"
## Physics layer 4, [code]fauna[/code].
const LAYER: int = 1 << 3

## Species (model, gaits, animations). Set before entering the tree.
@export var species: AnimalSpecies
## Seed of this agent's own decisions (wander targets, pauses).
@export var decision_seed: int = 0

## Where the agent belongs (wanders around it); set on entering the tree when zero.
var home: Vector3 = Vector3.ZERO
## Random numbers for this agent's decisions (seeded with [member decision_seed]).
var rng := RandomNumberGenerator.new()

@onready var movement: MovementComponent = %MovementComponent
@onready var state_machine: StateMachine = %StateMachine
@onready var model_root: Node3D = %Model


func _enter_tree() -> void:
	if species != null:
		(get_node("MovementComponent") as MovementComponent).species = species


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1  # world
	rng.seed = decision_seed
	if home == Vector3.ZERO:
		home = global_position
	add_to_group(GROUP)
	add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	EventBus.origin_shifted.connect(_on_origin_shifted)
	if Animal.spawn_species_model(movement.species, model_root):
		(%AnimationController as AnimationController).initialize()


## Horizontal distance (m) to [param point].
func horizontal_distance_to(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _on_origin_shifted(offset: Vector3) -> void:
	home -= offset
