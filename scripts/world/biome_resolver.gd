class_name BiomeResolver
extends RefCounted
## Resolves which biomes apply at an absolute position: distance from the spawn point,
## pushed in or out by low-frequency noise so boundaries look organic, selects a band of the
## [BiomeTable]; neighbouring bands cross-fade over [member BiomeTable.blend_width].
##
## Weights always sum to exactly 1 (at most two biomes mix, since the blend is never wider
## than a band) and are continuous. Pure and self-contained like [HeightSampler]: build one
## per worker task from a table copy and the world seed.
## [br][br]
## Budget: 1 noise lookup + O(bands per cycle) float ops per sample; [method blend_into]
## does not allocate.

## Seed salt for the boundary noise (decorrelated from the height layers).
const NOISE_SALT: int = 0xB10E

var _biomes: Array[BiomeDefinition] = []
var _starts := PackedFloat64Array()
var _sequence_length: float = 0.0
var _cycle: bool = false
var _half_blend: float = 0.0
var _noise_amplitude: float = 0.0
var _spawn: Vector2 = Vector2.ZERO
var _noise: FastNoiseLite
var _scratch := BiomeBlend.new()


func _init(table: BiomeTable, world_seed: int) -> void:
	_biomes = table.biomes.duplicate()
	_cycle = table.cycle
	_half_blend = table.blend_width * 0.5
	_noise_amplitude = table.boundary_noise_amplitude
	_spawn = table.spawn
	var start := 0.0
	for biome in _biomes:
		_starts.append(start)
		start += biome.band_width
	_sequence_length = start
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = HeightSampler.layer_seed(world_seed, NOISE_SALT)
	_noise.frequency = table.boundary_noise_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


## Distance from spawn after the boundary noise has pushed it in or out (m).
func effective_distance(x: float, z: float) -> float:
	var distance := Vector2(x, z).distance_to(_spawn)
	return distance + _noise.get_noise_2d(x, z) * _noise_amplitude


## Fills [param out] with the blended biome values at absolute ([param x], [param z]).
func blend_into(x: float, z: float, out: BiomeBlend) -> void:
	var d := effective_distance(x, z)
	var k := band_index(d)
	var start := band_start(k)
	var end := start + _band(k).band_width
	var neighbour := -1
	var neighbour_weight := 0.0
	if k > 0 and d < start + _half_blend:
		neighbour = k - 1
		neighbour_weight = 1.0 - smoothstep(start - _half_blend, start + _half_blend, d)
	elif _has_band_after(k) and d > end - _half_blend:
		neighbour = k + 1
		neighbour_weight = smoothstep(end - _half_blend, end + _half_blend, d)
	var own := _band(k)
	if neighbour < 0 or neighbour_weight <= 0.0:
		_fill(out, own, null, 0.0)
	elif neighbour_weight > 0.5:
		_fill(out, _band(neighbour), own, 1.0 - neighbour_weight)
	else:
		_fill(out, own, _band(neighbour), neighbour_weight)


## Biome weights at absolute ([param x], [param z]), keyed by biome id. Sums to 1.
## Allocates a dictionary: use [method blend_into] in hot paths.
func weights_at(x: float, z: float) -> Dictionary[StringName, float]:
	blend_into(x, z, _scratch)
	var weights: Dictionary[StringName, float] = {}
	weights[_scratch.primary.id] = 1.0 - _scratch.secondary_weight
	if _scratch.secondary != null:
		var id := _scratch.secondary.id
		weights[id] = weights.get(id, 0.0) + _scratch.secondary_weight
	return weights


## Biome with the largest weight at absolute ([param x], [param z]).
func dominant_at(x: float, z: float) -> BiomeDefinition:
	blend_into(x, z, _scratch)
	return _scratch.primary


## Global band index (counting bands across cycles) containing effective distance [param d].
func band_index(d: float) -> int:
	if d <= 0.0:
		return 0
	var n := _biomes.size()
	var cycles := 0
	var rest := d
	if _cycle:
		cycles = floori(d / _sequence_length)
		rest = d - cycles * _sequence_length
	elif d >= _sequence_length:
		return n - 1
	var local := n - 1
	for i in range(n - 1, -1, -1):
		if rest >= _starts[i]:
			local = i
			break
	return cycles * n + local


## Effective distance at which global band [param k] starts.
func band_start(k: int) -> float:
	var n := _biomes.size()
	return floorf(float(k) / n) * _sequence_length + _starts[k % n]


## Biome of global band [param k].
func biome_of_band(k: int) -> BiomeDefinition:
	return _band(k)


func _band(k: int) -> BiomeDefinition:
	return _biomes[k % _biomes.size()] if _cycle else _biomes[mini(k, _biomes.size() - 1)]


func _has_band_after(k: int) -> bool:
	return _cycle or k < _biomes.size() - 1


func _fill(
	out: BiomeBlend, primary: BiomeDefinition, secondary: BiomeDefinition, weight: float
) -> void:
	out.primary = primary
	out.secondary = secondary
	out.secondary_weight = weight
	if secondary == null:
		out.height_offset = primary.height_offset
		out.continental_scale = primary.continental_scale
		out.detail_scale = primary.detail_scale
		out.ridged_scale = primary.ridged_scale
		out.color_a = primary.ground_color_a
		out.color_b = primary.ground_color_b
		return
	out.height_offset = lerpf(primary.height_offset, secondary.height_offset, weight)
	out.continental_scale = lerpf(primary.continental_scale, secondary.continental_scale, weight)
	out.detail_scale = lerpf(primary.detail_scale, secondary.detail_scale, weight)
	out.ridged_scale = lerpf(primary.ridged_scale, secondary.ridged_scale, weight)
	out.color_a = primary.ground_color_a.lerp(secondary.ground_color_a, weight)
	out.color_b = primary.ground_color_b.lerp(secondary.ground_color_b, weight)
