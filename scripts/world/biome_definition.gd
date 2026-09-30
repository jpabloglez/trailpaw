class_name BiomeDefinition
extends Resource
## Data for one biome: its band width along the distance-from-spawn axis, how it reshapes
## the terrain and its ground palette. Lives under [code]data/biomes/[/code].
##
## Height modifiers are applied on top of [TerrainSettings]: offsets are added, scales
## multiply the layer amplitudes. Biomes are blended linearly by [code]BiomeResolver[/code],
## so the terrain changes smoothly across band boundaries. Defaults are neutral: values
## come from data (see [method get_validation_errors]).

## Stable identifier used in events and saves (e.g. [code]&"meadow"[/code]).
@export var id: StringName = &""
## Name shown to the player.
@export var display_name: String = ""
## Width of this biome's band along the distance-from-spawn axis.
@export_range(1.0, 10000.0, 1.0, "suffix:m") var band_width: float = 0.0

@export_group("Height")
## Added to the terrain height.
@export_range(-50.0, 50.0, 0.1, "suffix:m") var height_offset: float = 0.0
## Multiplier for the continental layer amplitude.
@export_range(0.0, 5.0, 0.01) var continental_scale: float = 0.0
## Multiplier for the detail layer amplitude.
@export_range(0.0, 5.0, 0.01) var detail_scale: float = 0.0
## Multiplier for the ridged layer amplitude.
@export_range(0.0, 5.0, 0.01) var ridged_scale: float = 0.0

@export_group("Climate")
## How warm the biome feels (-1 cool … +1 warm). Warm biomes lower temperature comfort, cool
## ones restore it ([code]NeedsModel[/code]).
@export_range(-1.0, 1.0, 0.05) var warmth: float = 0.0

@export_group("Vegetation")
## What grows in this biome and where (see [VegetationEntry]).
@export var vegetation: Array[VegetationEntry] = []

@export_group("Fauna")
## Chance that a full-detail chunk of this biome hosts a herd.
@export_range(0.0, 1.0, 0.01) var fauna_chance: float = 0.0
## Species living here and their relative weights.
@export var fauna: Array[FaunaEntry] = []

@export_group("Ground palette")
## First ground colour; the terrain shader varies between A and B across the landscape.
@export var ground_color_a: Color = Color.BLACK
## Second ground colour.
@export var ground_color_b: Color = Color.BLACK


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if band_width <= 0.0:
		errors.append("band_width must be > 0")
	if continental_scale < 0.0 or detail_scale < 0.0 or ridged_scale < 0.0:
		errors.append("height scales must be >= 0")
	if warmth < -1.0 or warmth > 1.0:
		errors.append("warmth must be within [-1, 1]")
	for i in vegetation.size():
		if vegetation[i] == null:
			errors.append("vegetation[%d] is null" % i)
			continue
		for problem: String in vegetation[i].get_validation_errors():
			errors.append("vegetation[%d]: %s" % [i, problem])
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
