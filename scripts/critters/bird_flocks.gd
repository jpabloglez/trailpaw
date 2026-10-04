class_name BirdFlocks
extends Node3D
## Songbirds you can see: flocks of 4–9 perched on treetops or pecking on the ground, flying on
## to another perch every so often and bursting into the air when the fox runs or jumps close.
## At night they roost. The birdsong follows them: [method presence] tells the ambience how many
## perched birds are near the listener.
##
## Like the [CritterSystem], birds live in packed arrays and draw as one [MultiMeshInstance3D];
## the wings flap in [code]shaders/bird.gdshader[/code] from per-instance data. A full-detail
## chunk rolls its flock (deterministic per seed and chunk) when it loads; the flock leaves with
## the chunk. Each flight is an arc from perch to perch, each bird with its own speed and spot.
## [br][br]
## Budget: decisions at 15 Hz (a few comparisons per flock); per frame one transform and custom
## data per bird (≤ [member BirdSettings.max_birds]); treetops are gathered only when a flock
## picks a new perch.

## Flock states.
enum State { PERCHED, FLYING }

## Decision ticks per second.
const TICK_HZ: float = 15.0
## Seed salt for flock rolls.
const SALT: int = 0xB1D5

## Where, how many, how they behave.
@export var settings: BirdSettings
## Terrain (heights, biomes, chunk size).
@export var terrain: TerrainSettings
## Source of loaded chunks and treetops (optional; tests call [method sync]).
@export var streamer: WorldStreamer
## The player (scaring); defaults to the [code]player[/code] group.
@export var player: Node3D
## Day and night (roosting); optional, always day without it.
@export var day_night: DayNightCycle

var _sampler: HeightSampler
var _sampler_seed: int = -1
var _resolver: BiomeResolver
var _rng := RandomNumberGenerator.new()
var _rolled: Dictionary[Vector2i, bool] = {}
var _since_tick: float = 0.0
var _player_previous := Vector3.INF
var _player_speed: float = 0.0
var _player_climb: float = 0.0
var _tops := PackedVector3Array()
var _multimesh: MultiMesh
# Flocks.
var _f_chunk: Array[Vector2i] = []
var _f_state := PackedInt32Array()
var _f_timer := PackedFloat32Array()
var _f_colour := PackedColorArray()
# Birds (their flock's index; flights from → to with an arc).
var _b_flock := PackedInt32Array()
var _b_from := PackedVector3Array()
var _b_to := PackedVector3Array()
var _b_t := PackedFloat32Array()
var _b_seconds := PackedFloat32Array()
var _b_arc := PackedFloat32Array()
var _b_phase := PackedFloat32Array()
var _b_yaw := PackedFloat32Array()


func _ready() -> void:
	_rng.seed = 0xB12D
	var node := MultiMeshInstance3D.new()
	node.name = "Birds"
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = ProceduralMeshes.bird()
	_multimesh.instance_count = settings.max_birds
	_multimesh.visible_instance_count = 0
	node.multimesh = _multimesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/bird.gdshader")
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	EventBus.origin_shifted.connect(_on_origin_shifted)
	if streamer != null:
		streamer.chunks_changed.connect(sync_from_streamer)


func _physics_process(delta: float) -> void:
	_since_tick += delta
	if _since_tick >= 1.0 / TICK_HZ:
		tick(_since_tick)
		_since_tick = 0.0


func _process(delta: float) -> void:
	advance(delta)
	draw()


## Syncs with the [member streamer]'s full-detail chunks.
func sync_from_streamer() -> void:
	var lod0: Array[Vector2i] = []
	for coord in streamer.loaded_coords():
		if streamer.get_chunk(coord).lod == 0:
			lod0.append(coord)
	sync(lod0)


## Rolls the flocks of newly available full-detail chunks and drops those whose chunk is gone.
func sync(lod0_coords: Array[Vector2i]) -> void:
	var available := {}
	for coord in lod0_coords:
		available[coord] = true
	for f in range(_f_chunk.size() - 1, -1, -1):
		if not available.has(_f_chunk[f]):
			_remove_flock(f)
	for coord: Vector2i in _rolled.keys():
		if not available.has(coord):
			_rolled.erase(coord)
	for coord in lod0_coords:
		if _rolled.has(coord):
			continue
		_rolled[coord] = true
		var flock := roll(
			coord, _biome_at(coord), settings, GameState.world_seed, terrain.chunk_size
		)
		if flock.is_empty() or _b_flock.size() + int(flock[0]) > settings.max_birds:
			continue
		_add_flock(coord, flock)


## The flock chunk [param coord] hosts in [param biome_id]: [code][size, colour index, absolute
## centre xz][/code], or empty. Pure and deterministic per (seed, chunk).
static func roll(
	coord: Vector2i, biome_id: StringName, bird: BirdSettings, world_seed: int, chunk_size: float
) -> Array:
	var chance: float = bird.biome_chance.get(biome_id, 0.0)
	if chance <= 0.0:
		return []
	var rng := RandomNumberGenerator.new()
	var chunk_seed := HeightSampler.layer_seed(world_seed, coord.x * 73856093 ^ coord.y * 19349663)
	rng.seed = HeightSampler.layer_seed(chunk_seed, SALT)
	if rng.randf() >= chance:
		return []
	var size := rng.randi_range(bird.flock_size.x, bird.flock_size.y)
	var colour := rng.randi_range(0, maxi(0, bird.palette.size() - 1))
	var centre := Vector2(coord) + Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8))
	return [size, colour, centre * chunk_size]


## One decision tick: scaring, roosting, moving on.
func tick(elapsed: float) -> void:
	var focus := _player()
	var at := focus.global_position if focus != null else Vector3.INF
	if focus != null and _player_previous != Vector3.INF and elapsed > 0.0:
		_player_speed = Vector2(at.x - _player_previous.x, at.z - _player_previous.z).length()
		_player_speed /= elapsed
		_player_climb = (at.y - _player_previous.y) / elapsed
	_player_previous = at
	var day := daylight() > 0.3
	for f in _f_chunk.size():
		_f_timer[f] -= elapsed
		if _f_state[f] == State.FLYING:
			if _flock_landed(f):
				_f_state[f] = State.PERCHED
				_f_timer[f] = _rng.randf_range(settings.perch_seconds.x, settings.perch_seconds.y)
			continue
		if focus != null and _scared(f, at):
			_take_off(f, at)
		elif day and _f_timer[f] <= 0.0:
			_take_off(f, Vector3.INF)


## Moves every flight forward by [param delta] seconds.
func advance(delta: float) -> void:
	for b in _b_flock.size():
		if _b_t[b] < 1.0:
			_b_t[b] = minf(1.0, _b_t[b] + delta / maxf(_b_seconds[b], 0.05))


## Writes every bird's transform, flap and colour into the MultiMesh.
func draw() -> void:
	var shown := mini(_b_flock.size(), _multimesh.instance_count)
	for b in shown:
		var basis := Basis(Vector3.UP, _b_yaw[b])
		_multimesh.set_instance_transform(b, Transform3D(basis, position_of(b)))
		var flying := _b_t[b] < 1.0
		_multimesh.set_instance_custom_data(b, Color(1.0 if flying else 0.0, _b_phase[b], 0, 0))
		_multimesh.set_instance_color(b, _f_colour[_b_flock[b]])
	_multimesh.visible_instance_count = shown


## 0 at night … 1 by day (the inverse of the sky's stars); always day without a cycle.
func daylight() -> float:
	if day_night == null:
		return 1.0
	var hour := GameState.time_of_day() / 60.0
	return 1.0 - DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour)


## How much birdsong there should be at [param at] (local): 0 with no perched birds within
## [member BirdSettings.song_radius] or at night, 1 with
## [member BirdSettings.song_full_count] or more.
func presence(at: Vector3) -> float:
	if daylight() <= 0.3:
		return 0.0
	var near := 0
	var radius_sq := settings.song_radius * settings.song_radius
	for b in _b_flock.size():
		if _b_t[b] >= 1.0 and _b_to[b].distance_squared_to(at) <= radius_sq:
			near += 1
	return clampf(float(near) / settings.song_full_count, 0.0, 1.0)


## Birds alive.
func count() -> int:
	return _b_flock.size()


## Flocks alive.
func flock_count() -> int:
	return _f_chunk.size()


## State of flock [param f].
func flock_state(f: int) -> int:
	return _f_state[f]


## Where bird [param b] is now (local).
func position_of(b: int) -> Vector3:
	var t := _b_t[b]
	var p := _b_from[b].lerp(_b_to[b], smoothstep(0.0, 1.0, t))
	p.y += 4.0 * _b_arc[b] * t * (1.0 - t)
	return p


## Where bird [param b] is perched or flying to (local).
func perch_of(b: int) -> Vector3:
	return _b_to[b]


func _scared(f: int, at: Vector3) -> bool:
	if _player_speed <= settings.scare_speed and _player_climb <= 2.0:
		return false
	var radius_sq := settings.scare_radius * settings.scare_radius
	for b in _b_flock.size():
		if _b_flock[b] == f and _b_to[b].distance_squared_to(at) <= radius_sq:
			return true
	return false


func _flock_landed(f: int) -> bool:
	for b in _b_flock.size():
		if _b_flock[b] == f and _b_t[b] < 1.0:
			return false
	return true


func _flock_centre(f: int) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in _b_flock.size():
		if _b_flock[b] == f:
			sum += _b_to[b]
			n += 1
	return sum / maxf(n, 1)


# Sends flock [param f] to a new perch: away from [param threat] when scared (INF: a calm move).
func _take_off(f: int, threat: Vector3) -> void:
	var from := _flock_centre(f)
	var direction: Vector3
	var span := settings.move_distance
	if threat != Vector3.INF:
		direction = Vector3(from.x - threat.x, 0.0, from.z - threat.z)
		span = settings.flee_distance
	if direction == Vector3.ZERO or direction.length_squared() < 1e-6:
		var angle := _rng.randf() * TAU
		direction = Vector3(cos(angle), 0.0, sin(angle))
	direction = direction.normalized()
	var wanted := from + direction * _rng.randf_range(span.x, span.y)
	var perch := _perch_near(wanted)
	var on_tree := perch.y > _ground(perch) + 1.0
	_f_state[f] = State.FLYING
	for b in _b_flock.size():
		if _b_flock[b] != f:
			continue
		var start := position_of(b)
		var spot := _spot(perch, on_tree)
		var distance := start.distance_to(spot)
		_b_from[b] = start
		_b_to[b] = spot
		_b_t[b] = 0.0
		_b_seconds[b] = distance / (settings.flight_speed * _rng.randf_range(0.85, 1.15))
		_b_arc[b] = (
			settings.arc_height * _rng.randf_range(0.7, 1.3) * clampf(distance / 30.0, 0.3, 1.0)
		)
		_b_yaw[b] = atan2(-(spot.x - start.x), -(spot.z - start.z))


# A treetop near [param wanted] (local) if there is one within 15 m, else dry ground there.
func _perch_near(wanted: Vector3) -> Vector3:
	_tops.clear()
	if streamer != null:
		for coord in streamer.loaded_coords():
			var chunk := streamer.get_chunk(coord)
			if chunk != null and chunk.lod == 0:
				var origin := streamer.chunk_origin(coord)
				var size := terrain.chunk_size
				var close := Rect2(Vector2(origin.x, origin.z), Vector2(size, size)).grow(15.0)
				if close.has_point(Vector2(wanted.x, wanted.z)):
					chunk.tree_tops(_tops)
	var best := Vector3.INF
	var best_d := 15.0 * 15.0
	for top in _tops:
		var d := Vector2(top.x - wanted.x, top.z - wanted.z).length_squared()
		if d < best_d:
			best_d = d
			best = top
	if best != Vector3.INF:
		return best
	var ground := Vector3(wanted.x, _ground(wanted), wanted.z)
	if not is_inf(GameState.water_level) and ground.y < GameState.water_level + 0.1:
		ground.y = GameState.water_level + 0.1  # over water: they skim and settle by the shore
	return ground


# A spot for one bird at [param perch]: spread over the crown or a patch of ground.
func _spot(perch: Vector3, on_tree: bool) -> Vector3:
	var spread := settings.crown_spread if on_tree else settings.ground_spread
	var angle := _rng.randf() * TAU
	var spot := perch + Vector3(cos(angle), 0.0, sin(angle)) * sqrt(_rng.randf()) * spread
	if on_tree:
		spot.y = perch.y - _rng.randf() * 0.4
	else:
		spot.y = maxf(_ground(spot), GameState.water_level + 0.1)
	return spot


func _add_flock(coord: Vector2i, flock: Array) -> void:
	var f := _f_chunk.size()
	_f_chunk.append(coord)
	_f_state.append(State.PERCHED)
	_f_timer.append(_rng.randf_range(settings.perch_seconds.x, settings.perch_seconds.y))
	var colour := settings.palette[flock[1]] if not settings.palette.is_empty() else Color.WHITE
	_f_colour.append(colour)
	var centre: Vector2 = flock[2]
	var local := GameState.local_position(Vector3(centre.x, 0.0, centre.y))
	var perch := _perch_near(local)
	var on_tree := perch.y > _ground(perch) + 1.0
	for i in int(flock[0]):
		var spot := _spot(perch, on_tree)
		_b_flock.append(f)
		_b_from.append(spot)
		_b_to.append(spot)
		_b_t.append(1.0)
		_b_seconds.append(1.0)
		_b_arc.append(0.0)
		_b_phase.append(_rng.randf() * TAU)
		_b_yaw.append(_rng.randf() * TAU)


# Removes flock [param f] and its birds (the last flock takes its index).
func _remove_flock(f: int) -> void:
	var b := _b_flock.size() - 1
	while b >= 0:
		if _b_flock[b] == f:
			_remove_bird(b)
		b -= 1
	var last := _f_chunk.size() - 1
	if f != last:
		_f_chunk[f] = _f_chunk[last]
		_f_state[f] = _f_state[last]
		_f_timer[f] = _f_timer[last]
		_f_colour[f] = _f_colour[last]
		for i in _b_flock.size():
			if _b_flock[i] == last:
				_b_flock[i] = f
	_f_chunk.resize(last)
	_f_state.resize(last)
	_f_timer.resize(last)
	_f_colour.resize(last)


# Packed arrays are values in GDScript: each is handled by name.
func _remove_bird(b: int) -> void:
	var last := _b_flock.size() - 1
	_b_flock[b] = _b_flock[last]
	_b_from[b] = _b_from[last]
	_b_to[b] = _b_to[last]
	_b_t[b] = _b_t[last]
	_b_seconds[b] = _b_seconds[last]
	_b_arc[b] = _b_arc[last]
	_b_phase[b] = _b_phase[last]
	_b_yaw[b] = _b_yaw[last]
	_b_flock.resize(last)
	_b_from.resize(last)
	_b_to.resize(last)
	_b_t.resize(last)
	_b_seconds.resize(last)
	_b_arc.resize(last)
	_b_phase.resize(last)
	_b_yaw.resize(last)


func _ground(local: Vector3) -> float:
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed
		_resolver = null
	var at := GameState.absolute_position(local)
	return _sampler.height_at(at.x, at.z)


func _biome_at(coord: Vector2i) -> StringName:
	if terrain == null or terrain.biomes == null:
		return &""
	if _resolver == null:
		_resolver = BiomeResolver.new(terrain.biomes, GameState.world_seed)
	var centre := (Vector2(coord) + Vector2(0.5, 0.5)) * terrain.chunk_size
	return _resolver.dominant_at(centre.x, centre.y).id


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D


func _on_origin_shifted(offset: Vector3) -> void:
	for b in _b_flock.size():
		_b_from[b] -= offset
		_b_to[b] -= offset
	if _player_previous != Vector3.INF:
		_player_previous -= offset
