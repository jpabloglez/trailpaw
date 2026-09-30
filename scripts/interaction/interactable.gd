class_name Interactable
extends Area3D
## A discrete thing the player can interact with (a den, a test object…): an [Area3D] on the
## [code]interactable[/code] physics layer offering one [InteractionTarget].
##
## Add a [CollisionShape3D] child for its reach. Depleting sources ([member
## InteractionDefinition.regrowth_minutes] > 0) become unavailable when consumed.

## Emitted when an interaction with this object starts.
signal started
## Emitted when an interaction with this object completes.
signal consumed

## Physics layer 3, [code]interactable[/code].
const LAYER: int = 1 << 2

## What interacting does.
@export var definition: InteractionDefinition

## Whether it can be interacted with now.
var available: bool = true


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


## The target this object offers (the shape index does not matter).
func interaction_target(_shape_index: int) -> InteractionTarget:
	return InteractionTarget.new(definition, global_position, self)


## Provider protocol: whether the target is available.
func is_target_available(_key: int) -> bool:
	return available and definition != null


## Provider protocol: the interaction starts.
func begin_target(_key: int) -> void:
	started.emit()


## Provider protocol: the interaction completed.
func consume_target(_key: int) -> void:
	if definition.regrowth_minutes > 0.0:
		available = false
	consumed.emit()
