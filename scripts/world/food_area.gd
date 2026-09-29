class_name FoodArea
extends Area3D
## The food target shapes of one [TerrainChunk], on the [code]interactable[/code] layer. Hit by
## the [Interactor]'s shape cast, it forwards the interaction provider protocol to its chunk
## (shape owners created by the chunk, one sphere each).

## Chunk owning the food.
var chunk: TerrainChunk


func _init(owner_chunk: TerrainChunk = null) -> void:
	chunk = owner_chunk
	name = "Food"
	collision_layer = Interactable.LAYER
	collision_mask = 0
	monitoring = false


## Provider protocol: the target of food shape [param shape_index].
func interaction_target(shape_index: int) -> InteractionTarget:
	return chunk.target_for_shape(shape_index)


## Provider protocol: forwarded to the chunk.
func is_target_available(key: int) -> bool:
	return chunk.is_target_available(key)


## Provider protocol: forwarded to the chunk.
func consume_target(key: int) -> void:
	chunk.consume_target(key)
