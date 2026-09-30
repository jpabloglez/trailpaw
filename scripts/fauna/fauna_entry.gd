class_name FaunaEntry
extends Resource
## One species a biome hosts, with its relative weight (see [member BiomeDefinition.fauna]).

## The species.
@export var species: FaunaSpecies
## Relative chance among the biome's entries.
@export_range(0.0, 100.0, 0.01) var weight: float = 1.0
