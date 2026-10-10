class_name TerrainSettings
extends Resource
## Tunables for the procedural terrain height function (see [HeightSampler]).
##
## Three layers are summed: a low-frequency [b]continental[/b] swell, small [b]detail[/b]
## bumps and a [b]ridged[/b] layer masked by the continental value so ridges only rise on
## high ground. Defaults are deliberately neutral: values come from
## [code]data/world/terrain_settings.tres[/code] (see [method get_validation_errors]).

## LOD 0 grid spacing required for collision: [HeightMapShape3D] samples are 1 m apart.
const COLLISION_STEP: float = 1.0
## Maximum fractal octaves allowed per layer (keeps per-sample cost bounded).
const MAX_OCTAVES: int = 8

@export_group("Chunks")
## Side length of a square terrain chunk.
@export_range(8.0, 512.0, 1.0, "suffix:m") var chunk_size: float = 0.0
## Vertices per chunk side for each LOD level (index = LOD). [code]resolution - 1[/code] must
## divide evenly so coarser grids share vertex positions with finer ones.
@export var lod_resolutions: PackedInt32Array = PackedInt32Array()
## Depth of the vertical skirt around every chunk; hides cracks between chunks of
## different LOD (T-junctions) without neighbours knowing about each other.
@export_range(0.0, 20.0, 0.1, "suffix:m") var skirt_depth: float = 0.0

@export_group("Biomes")
## Biome bands that reshape and colour the terrain. Without a table the terrain is the
## plain layered noise (useful for tests).
@export var biomes: BiomeTable
## Rural hamlets (Phase 16, ADR-007); none when null.
@export var hamlets: HamletSettings

@export_group("Water")
## Absolute height of the water surface. Chunks with ground below it get a water plane
## (lakes and channels, mostly in the river valley).
@export_range(-100.0, 100.0, 0.1, "suffix:m") var sea_level: float = 0.0

@export_group("Snow")
## Absolute height above which the ground is snowy (the mountain peaks, Phase 17), and the
## height over which the snow fades in. Nothing grows above the snow line.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var snow_line: float = 1000.0
@export_range(0.5, 50.0, 0.5, "suffix:m") var snow_blend: float = 8.0

@export_group("Height")
## Height offset added to every sample.
@export_range(-100.0, 100.0, 0.1, "suffix:m") var base_height: float = 0.0

@export_group("Continental")
## Frequency of the continental layer (1 / wavelength).
@export_range(0.00001, 0.1, 0.00001, "suffix:1/m") var continental_frequency: float = 0.0
## Peak contribution of the continental layer.
@export_range(0.0, 200.0, 0.1, "suffix:m") var continental_amplitude: float = 0.0
## Fractal octaves of the continental layer.
@export_range(1, 8) var continental_octaves: int = 0

@export_group("Detail")
## Frequency of the detail layer.
@export_range(0.00001, 1.0, 0.00001, "suffix:1/m") var detail_frequency: float = 0.0
## Peak contribution of the detail layer.
@export_range(0.0, 50.0, 0.1, "suffix:m") var detail_amplitude: float = 0.0
## Fractal octaves of the detail layer.
@export_range(1, 8) var detail_octaves: int = 0

@export_group("Ridged")
## Frequency of the ridged layer.
@export_range(0.00001, 0.1, 0.00001, "suffix:1/m") var ridged_frequency: float = 0.0
## Peak contribution of the ridged layer (only on high continental ground).
@export_range(0.0, 200.0, 0.1, "suffix:m") var ridged_amplitude: float = 0.0
## Fractal octaves of the ridged layer.
@export_range(1, 8) var ridged_octaves: int = 0


## Returns human-readable problems with the tunables; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if chunk_size <= 0.0:
		errors.append("chunk_size must be > 0")
	if skirt_depth <= 0.0:
		errors.append("skirt_depth must be > 0")
	if lod_resolutions.is_empty():
		errors.append("lod_resolutions must list at least one LOD")
	if not lod_resolutions.is_empty() and not is_equal_approx(step_for_lod(0), COLLISION_STEP):
		errors.append(
			"LOD 0 vertex spacing must be %.1f m (HeightMapShape3D spacing)" % COLLISION_STEP
		)
	for i in lod_resolutions.size():
		var res := lod_resolutions[i]
		if res < 2:
			errors.append("lod_resolutions[%d] must be >= 2" % i)
		elif i > 0 and (lod_resolutions[0] - 1) % (res - 1) != 0:
			errors.append("lod_resolutions[%d] - 1 must divide lod_resolutions[0] - 1" % i)
	if biomes != null:
		for problem: String in biomes.get_validation_errors():
			errors.append("biomes: " + problem)
	for layer: String in ["continental", "detail", "ridged"]:
		if float(get(layer + "_frequency")) <= 0.0:
			errors.append("%s_frequency must be > 0" % layer)
		if float(get(layer + "_amplitude")) < 0.0:
			errors.append("%s_amplitude must be >= 0" % layer)
		var octaves := int(get(layer + "_octaves"))
		if octaves < 1 or octaves > MAX_OCTAVES:
			errors.append("%s_octaves must be within [1, %d]" % [layer, MAX_OCTAVES])
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()


## Vertices per side for [param lod].
func resolution_for_lod(lod: int) -> int:
	return lod_resolutions[lod]


## Distance between neighbouring vertices at [param lod].
func step_for_lod(lod: int) -> float:
	return chunk_size / float(lod_resolutions[lod] - 1)
