class_name Flitters
extends Node3D
## Small fliers of one [FlitterKind] around the player, each visiting a spot of the nearby
## chunks (butterflies: flowers; dragonflies: reeds and water lilies), flying around it (or
## darting about it) and now and then on to a nearby one. Running through them scatters them
## up and away; out of their hours, in other biomes or on the Low preset there are none. Drawn
## as one [MultiMeshInstance3D]; the wings flap in [code]shaders/bird.gdshader[/code].
## [br][br]
## Budget: spots are gathered twice a second from the full-detail chunks near the player;
## per frame ≤ [member FlitterKind.max_count] small updates.

## What they are and how they behave.
@export var kind: FlitterKind
## Source of the spots (optional; tests set [member spot_source]).
@export var streamer: WorldStreamer
## The player; defaults to the [code]player[/code] group.
@export var player: Node3D
## Day and night (optional; always day without it).
@export var day_night: DayNightCycle

## Returns the spots near the player (global positions); defaults to the streamer's chunks.
var spot_source: Callable

var _rng := RandomNumberGenerator.new()
var _multimesh: MultiMesh
var _spots := PackedVector3Array()
var _since_gather: float = 0.0
var _player_previous := Vector3.INF
var _player_speed: float = 0.0
var _time: float = 0.0
var _home := PackedVector3Array()
var _pos := PackedVector3Array()
var _scatter := PackedFloat32Array()  # seconds left scattering (0: visiting a spot)
var _away := PackedVector3Array()
var _phase := PackedFloat32Array()
var _colour := PackedColorArray()
var _target := PackedVector3Array()  # darting: the point it dashes to (offset from its spot)
var _wait := PackedFloat32Array()  # darting: seconds of hovering left
var _facing := PackedVector3Array()


func _ready() -> void:
	_rng.seed = 0xB077 ^ hash(kind.id)
	if not spot_source.is_valid():
		spot_source = _streamer_spots
	var node := MultiMeshInstance3D.new()
	node.name = String(kind.id).capitalize()
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = (
		ProceduralMeshes.dragonfly() if kind.shape == &"dragonfly" else ProceduralMeshes.butterfly()
	)
	_multimesh.instance_count = kind.max_count
	_multimesh.visible_instance_count = 0
	node.multimesh = _multimesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/bird.gdshader")
	material.set_shader_parameter(&"flap_rate", kind.flap_rate)
	material.set_shader_parameter(&"flap_angle", kind.flap_angle)
	material.set_shader_parameter(&"shoulder", Vector2(0.004, 0.0))
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	EventBus.origin_shifted.connect(_on_origin_shifted)


func _process(delta: float) -> void:
	step(delta)
	draw()


## Advances everything by [param delta] seconds (gathering spots, comings and goings,
## flying about and scattering).
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
		_spots = spot_source.call() if active() else PackedVector3Array()
		_balance(at)
	for i in _pos.size():
		var before := _pos[i]
		_move(i, at, delta)
		var moved := _pos[i] - before
		if moved.length_squared() > 1e-8:
			_facing[i] = moved.normalized()


## Whether they are out: in their hours (by day or at night), in their biomes, unless the
## preset turns them off.
func active() -> bool:
	if Settings.quality != null and not Settings.quality.motion_effects:
		return false
	if not kind.biomes.has(GameState.current_biome):
		return false
	if day_night == null:
		return kind.by_day
	var hour := GameState.time_of_day() / 60.0
	var night := DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour)
	return (night < 0.5) == kind.by_day


## Writes their transforms, wing beats and colours.
func draw() -> void:
	for i in _pos.size():
		var forward := Vector3(_facing[i].x, 0.0, _facing[i].z)
		if forward.length_squared() < 1e-6:
			forward = Vector3.FORWARD
		var basis := Basis.looking_at(forward, Vector3.UP).scaled(Vector3.ONE * kind.size)
		_multimesh.set_instance_transform(i, Transform3D(basis, _pos[i]))
		_multimesh.set_instance_custom_data(i, Color(1.0, _phase[i], 0, 0))
		_multimesh.set_instance_color(i, _colour[i])
	_multimesh.visible_instance_count = _pos.size()


## Fliers out now.
func count() -> int:
	return _pos.size()


## Where flier [param i] is (global).
func position_of(i: int) -> Vector3:
	return _pos[i]


## The spot flier [param i] visits (global).
func spot_of(i: int) -> Vector3:
	return _home[i]


## Whether flier [param i] is scattering.
func is_scattering(i: int) -> bool:
	return _scatter[i] > 0.0


# Moves flier [param i]: scattering, getting scared by the fox at [param at], or flying about
# its spot (a wobbly loop, or hovering and darting).
func _move(i: int, at: Vector3, delta: float) -> void:
	if _scatter[i] > 0.0:
		_scatter[i] -= delta
		_pos[i] += (_away[i] + Vector3.UP * 0.5) * kind.scatter_speed * delta
		if _scatter[i] <= 0.0:
			_home[i] = _pick_spot(at, _pos[i])
		return
	if _player_speed > kind.scare_speed and _pos[i].distance_to(at) < kind.scare_radius:
		var away := Vector3(_pos[i].x - at.x, 0.0, _pos[i].z - at.z)
		_away[i] = away.normalized() if away.length_squared() > 1e-6 else Vector3.RIGHT
		_scatter[i] = 1.5
		return
	var target: Vector3
	if kind.darts:
		target = _home[i] + _target[i]
		if _pos[i].distance_to(target) < 0.02:
			_wait[i] -= delta
			if _wait[i] <= 0.0:  # dash to a new point around the spot
				var angle := _rng.randf() * TAU
				var reach := _rng.randf() * kind.loop_radius
				var lift := kind.hover_height + _rng.randf_range(-1.0, 1.0) * kind.hover_wobble
				_target[i] = Vector3(cos(angle) * reach, lift, sin(angle) * reach)
				_wait[i] = _rng.randf_range(kind.hover_seconds.x, kind.hover_seconds.y)
	else:
		var t := _time * kind.loop_rate + _phase[i]
		var loop := kind.loop_radius
		target = (
			_home[i]
			+ Vector3(
				sin(t) * loop,
				kind.hover_height + sin(t * 2.3) * kind.hover_wobble,
				cos(t * 0.8) * loop
			)
		)
	_pos[i] = _pos[i].move_toward(target, kind.flit_speed * delta)
	if _rng.randf() < delta / kind.stay_seconds:  # now and then, on to another spot
		_home[i] = _pick_spot(at, _home[i])


# Adds fliers over spots near the player up to one per few spots, and lets go of those far
# away (or all of them when they are not out).
func _balance(at: Vector3) -> void:
	for i in range(_pos.size() - 1, -1, -1):
		if _spots.is_empty() or _pos[i].distance_to(at) > kind.radius * 1.5:
			_remove(i)
	var wanted := mini(kind.max_count, _spots.size() / kind.spots_per_flier)
	while _pos.size() < wanted:
		var spot := _spots[_rng.randi() % _spots.size()]
		_home.append(spot)
		_pos.append(spot + Vector3(0, kind.hover_height, 0))
		_scatter.append(0.0)
		_away.append(Vector3.ZERO)
		_phase.append(_rng.randf() * TAU)
		_target.append(Vector3(0, kind.hover_height, 0))
		_wait.append(_rng.randf_range(kind.hover_seconds.x, kind.hover_seconds.y))
		_facing.append(Vector3.FORWARD)
		var palette := kind.palette
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
	_target[i] = _target[last]
	_wait[i] = _wait[last]
	_facing[i] = _facing[last]
	_target.resize(last)
	_wait.resize(last)
	_facing.resize(last)
	_home.resize(last)
	_pos.resize(last)
	_scatter.resize(last)
	_away.resize(last)
	_phase.resize(last)
	_colour.resize(last)


# A spot near [param near] (within 8 m) and not too far from the player, else any spot.
func _pick_spot(at: Vector3, near: Vector3) -> Vector3:
	if _spots.is_empty():
		return near
	for attempt in 6:
		var spot := _spots[_rng.randi() % _spots.size()]
		if spot.distance_to(near) < 8.0 and spot.distance_to(at) < kind.radius:
			return spot
	return _spots[_rng.randi() % _spots.size()]


func _streamer_spots() -> PackedVector3Array:
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
		if not area.grow(kind.radius).has_point(at):
			continue  # no spot of this chunk is within reach
		var before := out.size()
		chunk.spots(kind.spots, out)
		var kept := before
		for i in range(before, out.size()):  # only spots within reach of the player
			if out[i].distance_to(focus.global_position) <= kind.radius:
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
	for i in _spots.size():
		_spots[i] -= offset
	if _player_previous != Vector3.INF:
		_player_previous -= offset
