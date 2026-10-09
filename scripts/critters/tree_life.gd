class_name TreeLife
extends Node3D
## Critters that live in the trees (Phase 15b), in packed arrays with one [MultiMeshInstance3D]
## per kind like the [CritterSystem]:
## [br]- [b]climbers[/b] (squirrels) forage in short hops around the foot of their tree; when the
##   fox comes running they dash up the trunk and cling to it under the crown, stay there a while
##   and come back down once it has gone;
## [br]- [b]perchers[/b] (owls) sit on a tree top, turn their head now and then and hoot; scared,
##   they fly with beating wings ([code]shaders/bird.gdshader[/code]) to another tree top nearby.
## [br]Each full-detail chunk picks, seeded per (world seed, chunk, kind), which of its trees host
## them; [member CritterKind.hours] says when they are out (otherwise they are not simulated,
## drawn or seen).
## [br][br]
## Budget: tree tops are read once per chunk roll (and each tree's foot sampled once); decisions
## at [member CritterSettings.sim_hz] (beyond [member CritterSettings.far_distance] every third
## tick) with ≤ 1 height sample per hop; each frame one transform per critter.

## Critter states.
enum State { GROUND, UP, PERCH, FLY }

## Squirrels cling to the trunk this far up from its foot to the crown's top point (below the
## foliage, where they can be seen), this far out from its axis (m).
const CLIMB_HEIGHT: float = 0.45
const TRUNK_RADIUS: float = 0.18
## A tree's "top" spot ([method TerrainChunk.spots]) is this fraction of its height; owls sit
## on the real top, a little above it.
const TOP_SPOT: float = 0.92

## Kinds that live in the trees ([code]&"climber"[/code] or [code]&"percher"[/code]).
@export var kinds: Array[CritterKind] = []
## Simulation rate.
@export var settings: CritterSettings
## Terrain (heights, biomes, chunk size).
@export var terrain: TerrainSettings
## Source of loaded chunks and their trees (optional; tests set [member tree_source]).
@export var streamer: WorldStreamer
## The player (scares them); defaults to the [code]player[/code] group.
@export var player: Node3D

## Returns the tree tops (local positions) of chunk [param coord]; defaults to the streamer's.
var tree_source: Callable
## Hoots so far (tests and tools).
var hoots: int = 0

var _sampler: HeightSampler
var _sampler_seed: int = -1
var _resolver: BiomeResolver
var _rng := RandomNumberGenerator.new()
var _rolled: Dictionary[Vector2i, PackedVector3Array] = {}  # chunk → its tree tops
var _since_tick: float = 0.0
var _player_previous := Vector3.INF
var _player_speed: float = 0.0
var _time: float = 0.0
var _out := PackedByteArray()
var _counts := PackedInt32Array()
var _kind := PackedInt32Array()
var _chunk: Array[Vector2i] = []
var _tree := PackedVector3Array()  # its tree's top
var _foot := PackedFloat32Array()  # ground height at its tree's foot (sampled once)
var _tick_count: int = 0
var _from := PackedVector3Array()
var _to := PackedVector3Array()
var _t := PackedFloat32Array()
var _seconds := PackedFloat32Array()
var _arc := PackedFloat32Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _call := PackedFloat32Array()  # owls: seconds to the next hoot
var _yaw := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _meshes: Array[MultiMeshInstance3D] = []
var _hoot: AudioStreamPlayer3D


func _ready() -> void:
	_rng.seed = 0x7EE
	if not tree_source.is_valid():
		tree_source = _streamer_trees
	for kind in kinds:
		var node := MultiMeshInstance3D.new()
		node.name = "Tree_" + String(kind.id)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = kind.behaviour == &"percher"  # (before the count)
		multimesh.use_colors = kind.behaviour == &"percher"
		multimesh.mesh = ProceduralMeshes.critter(kind.shape)
		multimesh.instance_count = 64
		multimesh.visible_instance_count = 0
		node.multimesh = multimesh
		if kind.behaviour == &"percher":
			var wings := ShaderMaterial.new()
			wings.shader = preload("res://shaders/bird.gdshader")
			wings.set_shader_parameter(&"flap_rate", 9.0)
			wings.set_shader_parameter(&"flap_angle", 0.8)
			wings.set_shader_parameter(&"tuck", 0.08)
			wings.set_shader_parameter(&"shoulder", Vector2(0.06, 0.22))
			node.material_override = wings
		else:
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.roughness = 0.9
			node.material_override = material
		add_child(node)
		_meshes.append(node)
	_counts.resize(kinds.size())
	_out.resize(kinds.size())
	_out.fill(1)
	_hoot = AudioStreamPlayer3D.new()
	_hoot.stream = SynthSounds.hoot()
	_hoot.bus = &"SFX"
	_hoot.unit_size = 10.0
	_hoot.max_distance = 70.0
	add_child(_hoot)
	EventBus.origin_shifted.connect(_on_origin_shifted)
	if streamer != null:
		streamer.chunks_changed.connect(sync_from_streamer)


func _physics_process(delta: float) -> void:
	_since_tick += delta
	if _since_tick >= 1.0 / settings.sim_hz:
		tick(_since_tick)
		_since_tick = 0.0


func _process(delta: float) -> void:
	_time += delta
	advance(delta)
	draw()


## Syncs with the [member streamer]'s full-detail chunks.
func sync_from_streamer() -> void:
	var lod0: Array[Vector2i] = []
	for coord in streamer.loaded_coords():
		if streamer.get_chunk(coord).lod == 0:
			lod0.append(coord)
	sync(lod0)


## Rolls newly available full-detail chunks and removes critters whose chunk is gone.
func sync(lod0_coords: Array[Vector2i]) -> void:
	var available := {}
	for coord in lod0_coords:
		available[coord] = true
	for i in range(_kind.size() - 1, -1, -1):
		if not available.has(_chunk[i]):
			_remove(i)
	for coord: Vector2i in _rolled.keys():
		if not available.has(coord):
			_rolled.erase(coord)
	for coord in lod0_coords:
		if not _rolled.has(coord):
			_roll(coord)


## One decision tick ([param elapsed] seconds since the last one).
func tick(elapsed: float) -> void:
	var focus := _player()
	var at := focus.global_position if focus != null else Vector3.INF
	if focus != null and _player_previous != Vector3.INF and elapsed > 0.0:
		_player_speed = Vector2(at.x - _player_previous.x, at.z - _player_previous.z).length()
		_player_speed /= elapsed
	_player_previous = at
	var hour := GameState.time_of_day() / 60.0
	for k in kinds.size():
		_out[k] = int(kinds[k].is_out(hour))
	_tick_count += 1
	for i in _kind.size():
		if _out[_kind[i]] == 0:
			continue
		var here := position_of(i)
		var distance := here.distance_to(at) if focus != null else INF
		var far := distance > settings.far_distance
		if far and (_tick_count + i) % 3 != 0:
			continue  # far away: every third tick
		var kind := kinds[_kind[i]]
		var step := elapsed * (3.0 if far else 1.0)
		_timer[i] -= step
		var scared := (
			distance < kind.startle_radius
			or (distance < kind.flee_radius and _player_speed > kind.flee_trigger_speed)
		)
		if kind.behaviour == &"percher":
			_perch_tick(i, kind, scared, distance, step)
		else:
			_climb_tick(i, kind, scared, distance)


## Moves every critter along its hop, climb or flight (every frame).
func advance(delta: float) -> void:
	for i in _kind.size():
		if _t[i] < 1.0:
			_t[i] = minf(1.0, _t[i] + delta / maxf(_seconds[i], 0.01))


## Writes every critter's transform into its kind's MultiMesh.
func draw() -> void:
	_counts.fill(0)
	for i in _kind.size():
		if not is_shown(i):
			continue
		var k := _kind[i]
		var multimesh := _meshes[k].multimesh
		var basis := Basis(Vector3.UP, _yaw[i]).scaled(Vector3.ONE * _scale[i])
		multimesh.set_instance_transform(_counts[k], Transform3D(basis, position_of(i)))
		if kinds[k].behaviour == &"percher":
			var flying := 1.0 if _state[i] == State.FLY and _t[i] < 1.0 else 0.0
			multimesh.set_instance_custom_data(_counts[k], Color(flying, _scale[i] * 30.0, 0, 0))
			multimesh.set_instance_color(_counts[k], Color.WHITE)
		_counts[k] += 1
	for k in kinds.size():
		_meshes[k].multimesh.visible_instance_count = _counts[k]


## Critters alive.
func count() -> int:
	return _kind.size()


## Critters alive of kind [param id].
func count_of(id: StringName) -> int:
	var k := kinds.find_custom(func(kind: CritterKind) -> bool: return kind.id == id)
	return _kind.count(k) if k >= 0 else 0


## Where critter [param i] is now (local).
func position_of(i: int) -> Vector3:
	var t := _t[i]
	var p := _from[i].lerp(_to[i], t)
	p.y += 4.0 * _arc[i] * t * (1.0 - t)
	return p


## The kind of critter [param i].
func kind_of(i: int) -> CritterKind:
	return kinds[_kind[i]]


## State of critter [param i] (a [enum State] value).
func state_of(i: int) -> int:
	return _state[i]


## The top of the tree critter [param i] lives in (local).
func tree_of(i: int) -> Vector3:
	return _tree[i]


## Whether critter [param i] is out (in its hours) and so drawn and seen.
func is_shown(i: int) -> bool:
	return _out[_kind[i]] == 1


# A squirrel: hops about the foot of its tree; scared, it runs up into the crown and comes back
# down once the fox has gone.
func _climb_tick(i: int, kind: CritterKind, scared: bool, distance: float) -> void:
	var base := Vector3(_tree[i].x, _foot[i], _tree[i].z)
	match _state[i]:
		State.GROUND:
			if scared:
				var here := position_of(i)
				var out := Vector3(here.x - base.x, 0.0, here.z - base.z)
				out = out.normalized() if out.length_squared() > 1e-4 else Vector3.RIGHT
				var up := base + out * TRUNK_RADIUS  # clinging to the trunk, under the crown
				up.y = lerpf(base.y, _tree[i].y, CLIMB_HEIGHT)
				_move(i, position_of(i), up, 0.0, 0.25 + 0.12 * (up.y - base.y))
				_state[i] = State.UP
				_timer[i] = kind.calm_seconds
			elif _t[i] >= 1.0 and _timer[i] <= 0.0:
				var angle := _rng.randf() * TAU
				var spot := (
					base
					+ Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.6, kind.home_radius)
				)
				spot.y = _ground(spot)
				_move(i, _to[i], spot, kind.graze_hop.y, kind.graze_hop.z * 2.0)
				_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
		State.UP:
			if scared:
				_timer[i] = kind.calm_seconds
			elif _t[i] >= 1.0 and _timer[i] <= 0.0 and distance > kind.flee_radius:
				var down := base + Vector3(cos(_yaw[i]), 0.0, sin(_yaw[i])) * 0.6
				down.y = _ground(down)
				_move(i, _to[i], down, 0.0, 1.2)
				_state[i] = State.GROUND
				_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)


# An owl: sits, turns its head, hoots; scared, flies to another tree top nearby.
func _perch_tick(i: int, kind: CritterKind, scared: bool, distance: float, elapsed: float) -> void:
	if _state[i] == State.FLY:
		if _t[i] >= 1.0:
			_state[i] = State.PERCH
			_timer[i] = _rng.randf_range(2.0, 5.0)
		return
	if scared:
		var to := _other_tree(i, kind)
		if to != Vector3.INF:
			_move(i, _to[i], perch_point(to), kind.flee_hop.y, kind.flee_hop.z)
			_tree[i] = to
			_foot[i] = _ground(to)
			_state[i] = State.FLY
			return
	if _timer[i] <= 0.0:  # looks somewhere else
		_yaw[i] += _rng.randf_range(-1.2, 1.2)
		_timer[i] = _rng.randf_range(2.0, 5.0)
	_call[i] -= elapsed
	if _call[i] <= 0.0:
		_call[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
		if distance < 60.0:
			hoots += 1
			if _hoot.is_inside_tree():
				_hoot.global_position = to_global(position_of(i))
				_hoot.pitch_scale = _rng.randf_range(0.9, 1.1)
				_hoot.play()


# A tree top spot within the owl's flight (half to 1.5 × flee_hop.x away) in loaded chunks, or INF.
func _other_tree(i: int, kind: CritterKind) -> Vector3:
	var here := _to[i]
	var best := Vector3.INF
	var best_gap := INF
	for coord: Vector2i in _rolled:
		for top in _rolled[coord]:
			var gap := absf(Vector2(top.x - here.x, top.z - here.z).length() - kind.flee_hop.x)
			if gap < best_gap and gap < kind.flee_hop.x * 0.5:
				best_gap = gap
				best = top
	return best


## Where an owl sits on the tree whose top spot is [param top]: the crown's real top.
func perch_point(top: Vector3) -> Vector3:
	var ground := _ground(top)
	return Vector3(top.x, ground + (top.y - ground) / TOP_SPOT + 0.03, top.z)


func _move(i: int, from: Vector3, to: Vector3, arc: float, seconds: float) -> void:
	_from[i] = from
	_to[i] = to
	_t[i] = 0.0
	_arc[i] = arc
	_seconds[i] = seconds
	if Vector2(to.x - from.x, to.z - from.z).length() > 0.05:
		_yaw[i] = atan2(-(to.x - from.x), -(to.z - from.z))


# Picks which trees of chunk [param coord] host each kind (seeded per world, chunk and kind).
func _roll(coord: Vector2i) -> void:
	var tops: PackedVector3Array = tree_source.call(coord)
	_rolled[coord] = tops
	if tops.is_empty():
		return
	var biome := _biome_at(coord)
	for k in kinds.size():
		var kind := kinds[k]
		if not kind.biome_counts.has(biome):
			continue
		var rng := RandomNumberGenerator.new()
		var chunk_seed := HeightSampler.layer_seed(
			GameState.world_seed, coord.x * 73856093 ^ coord.y * 19349663
		)
		rng.seed = HeightSampler.layer_seed(chunk_seed, CritterPlan.SALT ^ hash(kind.id))
		if rng.randf() >= kind.chance:
			continue
		var counts: Vector2i = kind.biome_counts[biome]
		for n in rng.randi_range(counts.x, counts.y):
			_spawn(k, coord, tops[rng.randi() % tops.size()], rng)


func _spawn(k: int, coord: Vector2i, top: Vector3, rng: RandomNumberGenerator) -> void:
	var kind := kinds[k]
	var at := perch_point(top)
	var state := State.PERCH
	if kind.behaviour == &"climber":
		var angle := rng.randf() * TAU
		at = top + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.6, kind.home_radius)
		at.y = _ground(at)
		state = State.GROUND
	_kind.append(k)
	_chunk.append(coord)
	_tree.append(top)
	_foot.append(_ground(top))
	_from.append(at)
	_to.append(at)
	_t.append(1.0)
	_seconds.append(1.0)
	_arc.append(0.0)
	_state.append(state)
	_timer.append(rng.randf_range(0.0, kind.idle_seconds.y))
	_call.append(rng.randf_range(0.0, kind.idle_seconds.y))
	_yaw.append(rng.randf() * TAU)
	_scale.append(rng.randf_range(kind.scale_range.x, kind.scale_range.y))


# Removes critter [param i] by moving the last one into its place (each packed array by name:
# they are values in GDScript).
func _remove(i: int) -> void:
	var last := _kind.size() - 1
	_kind[i] = _kind[last]
	_chunk[i] = _chunk[last]
	_tree[i] = _tree[last]
	_foot[i] = _foot[last]
	_from[i] = _from[last]
	_to[i] = _to[last]
	_t[i] = _t[last]
	_seconds[i] = _seconds[last]
	_arc[i] = _arc[last]
	_state[i] = _state[last]
	_timer[i] = _timer[last]
	_call[i] = _call[last]
	_yaw[i] = _yaw[last]
	_scale[i] = _scale[last]
	_kind.resize(last)
	_chunk.resize(last)
	_tree.resize(last)
	_foot.resize(last)
	_from.resize(last)
	_to.resize(last)
	_t.resize(last)
	_seconds.resize(last)
	_arc.resize(last)
	_state.resize(last)
	_timer.resize(last)
	_call.resize(last)
	_yaw.resize(last)
	_scale.resize(last)


func _streamer_trees(coord: Vector2i) -> PackedVector3Array:
	var out := PackedVector3Array()
	var chunk := streamer.get_chunk(coord) if streamer != null else null
	if chunk != null:
		chunk.spots(&"tree_top", out)
		for n in out.size():
			out[n] = to_local(out[n])
	return out


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
	for i in _kind.size():
		_tree[i] -= offset
		_from[i] -= offset
		_to[i] -= offset
	for coord: Vector2i in _rolled:
		var tops := _rolled[coord]
		for n in tops.size():
			tops[n] -= offset
		_rolled[coord] = tops
	if _player_previous != Vector3.INF:
		_player_previous -= offset
