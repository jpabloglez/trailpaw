class_name InteractionTarget
extends RefCounted
## One thing the player can interact with right now: its definition, where it is and who
## provides it.
##
## Providers are colliders on the [code]interactable[/code] physics layer (an [Interactable],
## or a chunk's food shapes) or virtual sources such as water. A provider implements
## [code]is_target_available(key) -> bool[/code] and [code]consume_target(key)[/code]; [member
## key] tells it which of its targets this is.

## What the interaction is and does.
var definition: InteractionDefinition
## Global position of the target.
var position: Vector3
## The provider.
var source: Object
## Provider-specific identifier (e.g. instance index).
var key: int = 0


func _init(
	target_definition: InteractionDefinition,
	target_position: Vector3,
	target_source: Object,
	target_key: int = 0
) -> void:
	definition = target_definition
	position = target_position
	source = target_source
	key = target_key


## Whether the provider still offers this target.
func is_available() -> bool:
	return is_instance_valid(source) and source.call(&"is_target_available", key)


## Tells the provider the interaction completed (it may deplete).
func consume() -> void:
	if is_instance_valid(source):
		source.call(&"consume_target", key)


## Whether [param other] is the same target (same provider and key).
func same_as(other: InteractionTarget) -> bool:
	return other != null and other.source == source and other.key == key
