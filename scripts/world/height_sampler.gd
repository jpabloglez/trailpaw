class_name HeightSampler
extends RefCounted
## Deterministic terrain height function: layered [FastNoiseLite] seeded from the world seed.
##
## Pure and self-contained: every instance owns its noise objects, so worker threads can each
## build their own sampler from a [TerrainSettings] copy without sharing state.
## Coordinates are [b]absolute[/b] world metres (never floating-origin local positions).
## [br][br]
## Budget: 3 noise lookups (+1 for the biome boundary) per [method height_at] call, +1 where
## a biome has dunes or mesas (the sand layers, Phase 18); no allocations after construction.

## Seed salt per layer so layers are decorrelated but still derived from one world seed
## (continental, detail, ridged, sand).
const LAYER_SALT: Array[int] = [0x1F3A, 0x5C27, 0x9E41, 0x3D17]

var _base_height: float
var _continental_amplitude: float
var _detail_amplitude: float
var _ridged_amplitude: float
var _resolver: BiomeResolver
var _blend := BiomeBlend.new()
var _continental: FastNoiseLite
var _detail: FastNoiseLite
var _ridged: FastNoiseLite
var _sand: FastNoiseLite
var _dune_k: float
var _dune_dir: Vector2
var _dune_amplitude: float
var _dune_warp: float
var _dune_sharpness: float
var _mesa_amplitude: float
var _mesa_threshold: float
var _mesa_softness: float


func _init(settings: TerrainSettings, world_seed: int) -> void:
	_base_height = settings.base_height
	if settings.biomes != null:
		_resolver = BiomeResolver.new(settings.biomes, world_seed)
	_continental_amplitude = settings.continental_amplitude
	_detail_amplitude = settings.detail_amplitude
	_ridged_amplitude = settings.ridged_amplitude
	_continental = _make_noise(
		world_seed,
		LAYER_SALT[0],
		settings.continental_frequency,
		settings.continental_octaves,
		FastNoiseLite.FRACTAL_FBM
	)
	_detail = _make_noise(
		world_seed,
		LAYER_SALT[1],
		settings.detail_frequency,
		settings.detail_octaves,
		FastNoiseLite.FRACTAL_FBM
	)
	_ridged = _make_noise(
		world_seed,
		LAYER_SALT[2],
		settings.ridged_frequency,
		settings.ridged_octaves,
		FastNoiseLite.FRACTAL_RIDGED
	)
	_sand = _make_noise(
		world_seed, LAYER_SALT[3], settings.sand_frequency, 2, FastNoiseLite.FRACTAL_FBM
	)
	_dune_k = TAU / settings.dune_wavelength * 0.5  # |sin| repeats every half period
	_dune_dir = Vector2.from_angle(deg_to_rad(settings.dune_direction_degrees))
	_dune_amplitude = settings.dune_amplitude
	_dune_warp = settings.dune_warp
	_dune_sharpness = settings.dune_sharpness
	_mesa_amplitude = settings.mesa_amplitude
	_mesa_threshold = settings.mesa_threshold
	_mesa_softness = settings.mesa_softness


## Terrain height (m) at absolute world position ([param x], [param z]).
func height_at(x: float, z: float) -> float:
	return sample(x, z, _blend)


## Height at ([param x], [param z]); also fills [param blend] with the biome values used
## there (colours for the mesh). Without a biome table [param blend] is left untouched and
## neutral modifiers (offset 0, scales 1) apply.
func sample(x: float, z: float, blend: BiomeBlend) -> float:
	if _resolver != null:
		_resolver.blend_into(x, z, blend)
	return sample_with_blend(x, z, blend)


## Height at ([param x], [param z]) using already-known biome values [param blend] (e.g. a
## chunk-wide uniform blend). Identical to [method sample] when [param blend] is the blend
## at that point.
func sample_with_blend(x: float, z: float, blend: BiomeBlend) -> float:
	if _resolver == null:
		return sample_with_modifiers(x, z, 0.0, 1.0, 1.0, 1.0)
	return sample_with_modifiers(
		x,
		z,
		blend.height_offset,
		blend.continental_scale,
		blend.detail_scale,
		blend.ridged_scale,
		blend.dune_scale,
		blend.mesa_scale
	)


## Core height function with explicit biome modifiers (offset added, scales multiply the
## layer amplitudes). Hot loops pass hoisted locals here to avoid per-sample object reads.
func sample_with_modifiers(
	x: float,
	z: float,
	offset: float,
	continental_scale: float,
	detail_scale: float,
	ridged_scale: float,
	dune_scale: float = 0.0,
	mesa_scale: float = 0.0
) -> float:
	var continental := _continental.get_noise_2d(x, z)
	var detail := _detail.get_noise_2d(x, z)
	# Ridges only rise where the continental layer is high (mask in [0, 1]).
	var ridge_mask := clampf(continental * 0.5 + 0.5, 0.0, 1.0)
	var ridged := _ridged.get_noise_2d(x, z) * ridge_mask
	var height := (
		_base_height
		+ offset
		+ continental * _continental_amplitude * continental_scale
		+ detail * _detail_amplitude * detail_scale
		+ ridged * _ridged_amplitude * ridged_scale
	)
	if dune_scale > 0.0 or mesa_scale > 0.0:
		height += _sand_layers(x, z, dune_scale, mesa_scale)
	return height


## Dunes and mesas at ([param x], [param z]) (Phase 18, ADR-009): one sand noise lookup warps
## the dune crests and raises flat-topped mesas where it passes the threshold; the dunes stop
## at a mesa's edge so its top stays flat.
func _sand_layers(x: float, z: float, dune_scale: float, mesa_scale: float) -> float:
	var sand := _sand.get_noise_2d(x, z)
	var plateau := 0.0
	if mesa_scale > 0.0:
		plateau = smoothstep(_mesa_threshold, _mesa_threshold + _mesa_softness, sand)
	var out := plateau * _mesa_amplitude * mesa_scale
	if dune_scale > 0.0:
		var phase := _dune_k * (x * _dune_dir.x + z * _dune_dir.y) + _dune_warp * sand
		var crest := pow(1.0 - absf(sin(phase)), _dune_sharpness)
		var size := 0.55 + 0.45 * sand  # big and small dunes, not a regular washboard
		out += crest * size * _dune_amplitude * dune_scale * (1.0 - plateau)
	return out


## The biome resolver used by this sampler, or [code]null[/code] without a biome table.
func resolver() -> BiomeResolver:
	return _resolver


## Upper bound of [code]|height_at() - base_height|[/code] (noise output is within [-1, 1]).
func max_deviation() -> float:
	var m := Vector4(0.0, 1.0, 1.0, 1.0) if _resolver == null else _resolver.max_modifiers()
	var sand := Vector2.ZERO if _resolver == null else _resolver.max_sand()
	return (
		m.x
		+ _continental_amplitude * m.y
		+ _detail_amplitude * m.z
		+ _ridged_amplitude * m.w
		+ _dune_amplitude * sand.x
		+ _mesa_amplitude * sand.y
	)


## Deterministic 31-bit seed for a layer, derived from the world seed.
##
## Uses an explicit integer mix (not [method @GlobalScope.hash]) so the same world seed
## keeps producing the same world across engine versions.
static func layer_seed(world_seed: int, salt: int) -> int:
	var h := (world_seed ^ (salt * 0x9E3779B1)) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0x7FFFFFFF


static func _make_noise(
	world_seed: int, salt: int, frequency: float, octaves: int, fractal: FastNoiseLite.FractalType
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = layer_seed(world_seed, salt)
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	return noise
