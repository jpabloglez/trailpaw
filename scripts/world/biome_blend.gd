class_name BiomeBlend
extends RefCounted
## Biome values blended at one position, filled by [method BiomeResolver.blend_into].
## Reused across samples so the hot path does not allocate.

## Blended [member BiomeDefinition.height_offset].
var height_offset: float = 0.0
## Blended [member BiomeDefinition.continental_scale].
var continental_scale: float = 0.0
## Blended [member BiomeDefinition.detail_scale].
var detail_scale: float = 0.0
## Blended [member BiomeDefinition.ridged_scale].
var ridged_scale: float = 0.0
## Blended [member BiomeDefinition.ground_color_a].
var color_a: Color = Color.BLACK
## Blended [member BiomeDefinition.ground_color_b].
var color_b: Color = Color.BLACK
## Biome with the larger weight.
var primary: BiomeDefinition
## The other biome being blended in, or [code]null[/code] inside a band.
var secondary: BiomeDefinition
## Weight of [member secondary] in [0, 0.5]; the primary has [code]1 - secondary_weight[/code].
var secondary_weight: float = 0.0
