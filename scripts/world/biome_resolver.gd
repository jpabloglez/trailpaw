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
var _offsets := PackedFloat32Array()
var _continental := PackedFloat32Array()
var _detail := PackedFloat32Array()
var _ridged := PackedFloat32Array()
var _color_a := PackedColorArray()
var _color_b := PackedColorArray()
var _starts := PackedFloat64Array()
var _sequence_length: float = 0.0
var _cycle: bool = false
var _half_blend: float = 0.0
var _noise_amplitude: float = 0.0
var _spawn: Vector2 = Vector2.ZERO
var _noise_slope: float = 0.0
var _noise: FastNoiseLite
var _scratch := BiomeBlend.new()


func _init(table: BiomeTable, world_seed: int) -> void:
	_biomes = table.biomes.duplicate()
	_cycle = table.cycle
	_half_blend = table.blend_width * 0.5
	_noise_amplitude = table.boundary_noise_amplitude
	_noise_slope = (
		table.boundary_noise_amplitude
		* table.boundary_noise_frequency
		* BiomeTable.NOISE_GRADIENT_FACTOR
	)
	_spawn = table.spawn
	var start := 0.0
	for biome in _biomes:
		_starts.append(start)
		start += biome.band_width
		_offsets.append(biome.height_offset)
		_continental.append(biome.continental_scale)
		_detail.append(biome.detail_scale)
		_ridged.append(biome.ridged_scale)
		_color_a.append(biome.ground_color_a)
		_color_b.append(biome.ground_color_b)
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
	var own := _slot(k)
	if neighbour < 0 or neighbour_weight <= 0.0:
		_fill(out, own, -1, 0.0)
	elif neighbour_weight > 0.5:
		_fill(out, _slot(neighbour), own, 1.0 - neighbour_weight)
	else:
		_fill(out, own, _slot(neighbour), neighbour_weight)


## If every point within [param radius] of absolute ([param x], [param z]) lies inside a
## single band, away from any cross-fade, fills [param out] with that band's values and
## returns [code]true[/code]; the blend is then exactly constant over the area. Uses a
## rigorous bound: the noisy distance changes by at most 1 + A·f·[constant
## BiomeTable.NOISE_GRADIENT_FACTOR] per metre.
func uniform_blend(x: float, z: float, radius: float, out: BiomeBlend) -> bool:
	var d := effective_distance(x, z)
	var reach := radius * (1.0 + _noise_slope)
	var k := band_index(d)
	var start := band_start(k)
	var end := start + _band(k).band_width
	var pure_from := start + _half_blend if k > 0 else -INF
	var pure_to := end - _half_blend if _has_band_after(k) else INF
	if d - reach <= pure_from or d + reach >= pure_to:
		return false
	_fill(out, _slot(k), -1, 0.0)
	return true


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
	return _biomes[_slot(k)]


## Index into the biome list for global band [param k].
func _slot(k: int) -> int:
	return k % _biomes.size() if _cycle else mini(k, _biomes.size() - 1)


func _has_band_after(k: int) -> bool:
	return _cycle or k < _biomes.size() - 1


func _fill(out: BiomeBlend, primary: int, secondary: int, weight: float) -> void:
	out.primary = _biomes[primary]
	out.secondary = _biomes[secondary] if secondary >= 0 else null
	out.secondary_weight = weight
	if secondary < 0:
		out.height_offset = _offsets[primary]
		out.continental_scale = _continental[primary]
		out.detail_scale = _detail[primary]
		out.ridged_scale = _ridged[primary]
		out.color_a = _color_a[primary]
		out.color_b = _color_b[primary]
		return
	out.height_offset = lerpf(_offsets[primary], _offsets[secondary], weight)
	out.continental_scale = lerpf(_continental[primary], _continental[secondary], weight)
	out.detail_scale = lerpf(_detail[primary], _detail[secondary], weight)
	out.ridged_scale = lerpf(_ridged[primary], _ridged[secondary], weight)
	out.color_a = _color_a[primary].lerp(_color_a[secondary], weight)
	out.color_b = _color_b[primary].lerp(_color_b[secondary], weight)


## Largest |height offset| + per-layer scale among all biomes (for height bounds).
func max_modifiers() -> Vector4:
	var bound := Vector4.ZERO
	for i in _biomes.size():
		bound.x = maxf(bound.x, absf(_offsets[i]))
		bound.y = maxf(bound.y, _continental[i])
		bound.z = maxf(bound.z, _detail[i])
		bound.w = maxf(bound.w, _ridged[i])
	return bound
