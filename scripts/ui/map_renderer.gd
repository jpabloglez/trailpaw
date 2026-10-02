class_name MapRenderer
extends RefCounted
## Draws the map image: a square of [member span] metres centred on [member centre] (absolute;
## north, −Z, up), where explored land is coloured by biome with a hillshade, water by depth,
## and unexplored land is left as fog without being sampled at all.
##
## Run [method run] on a [WorkerThreadPool] task. The job owns its [HeightSampler] and a
## snapshot of the explored cells (both built on the main thread), and the main thread reads
## [member image] only after the task completes.
## [br][br]
## Budget: at most (size + 1)² height samples (≈ 66 k for 256 px; a few hundred milliseconds
## when everything is explored), on a worker thread only.

## Result, set by [method run].
var image: Image
## [WorkerThreadPool] task id, set by the submitter.
var task_id: int = -1
## Map centre (absolute X, Z).
var centre: Vector2
## Metres across the map.
var span: float

var _sampler: HeightSampler
var _cells: Dictionary[Vector2i, bool]
var _cell_size: float
var _water_level: float
var _settings: MapSettings
var _blend := BiomeBlend.new()


func _init(
	sampler: HeightSampler,
	cells: Dictionary[Vector2i, bool],
	cell_size: float,
	map_centre: Vector2,
	map_span: float,
	water_level: float,
	settings: MapSettings
) -> void:
	_sampler = sampler
	_cells = cells
	_cell_size = cell_size
	centre = map_centre
	span = map_span
	_water_level = water_level
	_settings = settings


## Worker-thread entry point: fills [member image].
func run() -> void:
	image = render()


## Renders now (on the calling thread).
func render() -> Image:
	var size := _settings.image_size
	var mpp := span / size
	var heights := PackedFloat32Array()
	heights.resize((size + 1) * (size + 1))
	heights.fill(NAN)
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	var fog := _settings.fog_color
	for v in size:
		for u in size:
			var x := centre.x + (u + 0.5 - size * 0.5) * mpp
			var z := centre.y + (v + 0.5 - size * 0.5) * mpp
			var color := fog
			if _cells.has(Vector2i(floori(x / _cell_size), floori(z / _cell_size))):
				color = _land_or_water(x, z, u, v, mpp, heights)
			var i := (v * size + u) * 3
			bytes[i] = color.r8
			bytes[i + 1] = color.g8
			bytes[i + 2] = color.b8
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)


## Map pixel (fractional) of the absolute point ([param x], [param z]).
func pixel_of(x: float, z: float) -> Vector2:
	var size := _settings.image_size
	return Vector2(x - centre.x, z - centre.y) * (size / span) + Vector2.ONE * size * 0.5


func _land_or_water(
	x: float, z: float, u: int, v: int, mpp: float, heights: PackedFloat32Array
) -> Color:
	var h := _sampler.sample(x, z, _blend)
	if is_inf(_water_level) or h >= _water_level:
		var ground := _blend.color_a.lerp(_blend.color_b, 0.5)
		var east := _height(u + 1, v, x + mpp, z, heights)
		var south := _height(u, v + 1, x, z + mpp, heights)
		# Light from the north-west: slopes rising to the east or south face away from it.
		var slope := ((east - h) + (south - h)) / mpp
		return ground * clampf(1.0 - slope * _settings.shade, 0.55, 1.35)
	var depth := clampf((_water_level - h) / _settings.deep_depth, 0.0, 1.0)
	return _settings.shallow_color.lerp(_settings.deep_color, depth)


func _height(u: int, v: int, x: float, z: float, heights: PackedFloat32Array) -> float:
	var i := v * (_settings.image_size + 1) + u
	if is_nan(heights[i]):
		heights[i] = _sampler.height_at(x, z)
	return heights[i]
