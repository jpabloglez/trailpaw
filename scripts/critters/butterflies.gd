class_name Butterflies
extends Node3D
## Butterflies by day: a few around the player, each visiting a flower of the meadow (the
## chunks' flower instances), flitting over it and now and then on to a nearby one. Running
## through them scatters them up and away; at night, in other biomes or on the Low preset there
## are none. Drawn as one [MultiMeshInstance3D]; the wings flap in
## [code]shaders/bird.gdshader[/code] (faster than a bird's).
## [br][br]
## Budget: flowers are gathered twice a second from the full-detail chunks near the player;
## per frame ≤ [member SmallLifeSettings.max_butterflies] small updates.

## Drawn bigger than life (the mesh is ≈ 9 cm across) so they read from the player's camera.
const SIZE: float = 1.6

## How they behave.
@export var settings: SmallLifeSettings
## Source of the flowers (optional; tests set [member flower_source]).
@export var streamer: WorldStreamer
## The player; defaults to the [code]player[/code] group.
@export var player: Node3D
## Day and night (optional; always day without it).
@export var day_night: DayNightCycle

## Returns the flowers near the player (global positions); defaults to the streamer's chunks.
var flower_source: Callable

var _rng := RandomNumberGenerator.new()
var _multimesh: MultiMesh
var _flowers := PackedVector3Array()
var _since_gather: float = 0.0
var _player_previous := Vector3.INF
var _player_speed: float = 0.0
var _time: float = 0.0
var _home := PackedVector3Array()
var _pos := PackedVector3Array()
var _scatter := PackedFloat32Array()  # seconds left scattering (0: visiting a flower)
var _away := PackedVector3Array()
var _phase := PackedFloat32Array()
var _colour := PackedColorArray()


func _ready() -> void:
	_rng.seed = 0xB077
	if not flower_source.is_valid():
		flower_source = _streamer_flowers
	var node := MultiMeshInstance3D.new()
	node.name = "Butterflies"
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = ProceduralMeshes.butterfly()
	_multimesh.instance_count = settings.max_butterflies
	_multimesh.visible_instance_count = 0
	node.multimesh = _multimesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/bird.gdshader")
	material.set_shader_parameter(&"flap_rate", 30.0)
	material.set_shader_parameter(&"flap_angle", 1.25)
	material.set_shader_parameter(&"shoulder", Vector2(0.004, 0.0))
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	EventBus.origin_shifted.connect(_on_origin_shifted)


func _process(delta: float) -> void:
	step(delta)
	draw()


## Advances everything by [param delta] seconds (gathering flowers, comings and goings,
## flitting and scattering).
func step(delta: float) -> void:
	_time += delta
	var focus := _player()
	var at := focus.global_position if focus != null else Vector3.ZERO
	if _player_previous != Vector3.INF and delta > 0.0:
		_player_speed = (
			Vector2(at.x - _player_previous.x, at.z - _player_previous.z).length() / delta
		)
	_player_previous = at
	_since_gather += delta
	if _since_gather >= 0.5:
		_since_gather = 0.0
		_flowers = flower_source.call() if active() else PackedVector3Array()
		_balance(at)
	for i in _pos.size():
		if _scatter[i] > 0.0:
			_scatter[i] -= delta
			_pos[i] += (_away[i] + Vector3.UP * 0.5) * settings.scatter_speed * delta
			if _scatter[i] <= 0.0:
				_home[i] = _pick_flower(at, _pos[i])
			continue
		if _player_speed > settings.scare_speed and _pos[i].distance_to(at) < settings.scare_radius:
			var away := Vector3(_pos[i].x - at.x, 0.0, _pos[i].z - at.z)
			_away[i] = away.normalized() if away.length_squared() > 1e-6 else Vector3.RIGHT
			_scatter[i] = 1.5
			continue
		# Flitting: a wobbly loop over the flower, drifting towards it.
		var t := _time * 1.3 + _phase[i]
		var target := (
			_home[i] + Vector3(sin(t) * 0.6, 0.75 + sin(t * 2.3) * 0.25, cos(t * 0.8) * 0.6)
		)
		_pos[i] = _pos[i].move_toward(target, settings.flit_speed * delta)
		if _rng.randf() < delta * 0.05:  # every ~20 s, on to another flower
			_home[i] = _pick_flower(at, _home[i])


## Whether butterflies are out: by day, in their biomes, unless the preset turns them off.
func active() -> bool:
	if Settings.quality != null and not Settings.quality.motion_effects:
		return false
	if not settings.butterfly_biomes.has(GameState.current_biome):
		return false
	if day_night == null:
		return true
	var hour := GameState.time_of_day() / 60.0
	return DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour) < 0.5


## Writes their transforms, wing beats and colours.
func draw() -> void:
	for i in _pos.size():
		var forward := Vector3(sin(_time + _phase[i]), 0.0, cos(_time + _phase[i]))
		var basis := Basis.looking_at(forward, Vector3.UP).scaled(Vector3.ONE * SIZE)
		_multimesh.set_instance_transform(i, Transform3D(basis, _pos[i]))
		_multimesh.set_instance_custom_data(i, Color(1.0, _phase[i], 0, 0))
		_multimesh.set_instance_color(i, _colour[i])
	_multimesh.visible_instance_count = _pos.size()


## Butterflies out now.
func count() -> int:
	return _pos.size()


## Where butterfly [param i] is (global).
func position_of(i: int) -> Vector3:
	return _pos[i]


## The flower butterfly [param i] visits (global).
func flower_of(i: int) -> Vector3:
	return _home[i]


## Whether butterfly [param i] is scattering.
func is_scattering(i: int) -> bool:
	return _scatter[i] > 0.0


# Adds butterflies over flowers near the player up to one per few flowers, and lets go of
# those far away (or all of them when they are not out).
func _balance(at: Vector3) -> void:
	for i in range(_pos.size() - 1, -1, -1):
		if _flowers.is_empty() or _pos[i].distance_to(at) > settings.butterfly_radius * 1.5:
			_remove(i)
	var wanted := mini(settings.max_butterflies, _flowers.size() / settings.flowers_per_butterfly)
	while _pos.size() < wanted:
		var flower := _flowers[_rng.randi() % _flowers.size()]
		_home.append(flower)
		_pos.append(flower + Vector3(0, 0.75, 0))
		_scatter.append(0.0)
		_away.append(Vector3.ZERO)
		_phase.append(_rng.randf() * TAU)
		var palette := settings.butterfly_palette
		_colour.append(
			palette[_rng.randi() % palette.size()] if not palette.is_empty() else Color.WHITE
		)


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_home[i] = _home[last]
	_pos[i] = _pos[last]
	_scatter[i] = _scatter[last]
	_away[i] = _away[last]
	_phase[i] = _phase[last]
	_colour[i] = _colour[last]
	_home.resize(last)
	_pos.resize(last)
	_scatter.resize(last)
	_away.resize(last)
	_phase.resize(last)
	_colour.resize(last)


# A flower near [param near] (within 8 m) and not too far from the player, else any flower.
func _pick_flower(at: Vector3, near: Vector3) -> Vector3:
	if _flowers.is_empty():
		return near
	for attempt in 6:
		var flower := _flowers[_rng.randi() % _flowers.size()]
		if flower.distance_to(near) < 8.0 and flower.distance_to(at) < settings.butterfly_radius:
			return flower
	return _flowers[_rng.randi() % _flowers.size()]


func _streamer_flowers() -> PackedVector3Array:
	var out := PackedVector3Array()
	var focus := _player()
	if streamer == null or focus == null:
		return out
	for coord in streamer.loaded_coords():
		var chunk := streamer.get_chunk(coord)
		if chunk == null or chunk.lod != 0:
			continue
		var size := streamer.terrain.chunk_size
		var area := Rect2(
			Vector2(streamer.chunk_origin(coord).x, streamer.chunk_origin(coord).z),
			Vector2(size, size)
		)
		var at := Vector2(focus.global_position.x, focus.global_position.z)
		if not area.grow(settings.butterfly_radius).has_point(at):
			continue  # no flower of this chunk is within reach
		var before := out.size()
		chunk.spots(&"flower", out)
		var kept := before
		for i in range(before, out.size()):  # only flowers within reach of the player
			if out[i].distance_to(focus.global_position) <= settings.butterfly_radius:
				out[kept] = out[i]
				kept += 1
		out.resize(kept)
	return out


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D


func _on_origin_shifted(offset: Vector3) -> void:
	for i in _pos.size():
		_pos[i] -= offset
		_home[i] -= offset
	for i in _flowers.size():
		_flowers[i] -= offset
	if _player_previous != Vector3.INF:
		_player_previous -= offset
