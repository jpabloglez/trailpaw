class_name CritterSystem
extends Node3D
## The critter layer: small animals (rabbits first) that live in packed arrays instead of as
## nodes — a light simulation plus one [MultiMeshInstance3D] per kind — so dozens of them cost
## less than one [FaunaAgent].
##
## Each full-detail chunk rolls its critters with [CritterPlan] when it loads and drops them when
## it stops being full detail. Calm critters graze with short hops around their home; when the
## fox comes running (closer than [member CritterKind.flee_radius], moving faster than
## [member CritterKind.flee_trigger_speed]) or bumps into them they flee in long zig-zag hops,
## then calm down where they are. Ground heights come from the [HeightSampler] (no rays, no
## physics bodies); hops never land in water or on steep ground.
## [br][br]
## Budget: decisions at [member CritterSettings.sim_hz] (critters beyond
## [member CritterSettings.far_distance] every 3rd tick), ≤ 2 height samples per hop; each frame
## one transform per critter. ≤ 1 ms for 120 critters (measured in tests). Arrays grow only
## when critters spawn.

## Critter states.
enum State { IDLE, HOP, FLEE }

## Kinds that live in this world.
@export var kinds: Array[CritterKind] = []
## Population and simulation.
@export var settings: CritterSettings
## Terrain (heights, biomes, chunk size).
@export var terrain: TerrainSettings
## Source of loaded chunks (optional; tests call [method sync] directly).
@export var streamer: WorldStreamer
## The player (fleeing); defaults to the [code]player[/code] group.
@export var player: Node3D

var _sampler: HeightSampler
var _sampler_seed: int = -1
var _resolver: BiomeResolver
var _rng := RandomNumberGenerator.new()
var _rolled: Dictionary[Vector2i, bool] = {}
var _since_tick: float = 0.0
var _tick_count: int = 0
var _player_previous := Vector3.INF
var _player_speed: float = 0.0
var _counts := PackedInt32Array()
# One entry per critter (struct of arrays; removal swaps with the last).
var _kind := PackedInt32Array()
var _chunk: Array[Vector2i] = []
var _home := PackedVector3Array()
var _from := PackedVector3Array()
var _to := PackedVector3Array()
var _t := PackedFloat32Array()
var _hop_seconds := PackedFloat32Array()
var _hop_height := PackedFloat32Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _zig := PackedFloat32Array()
var _meshes: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	_rng.seed = 0x5EED
	for kind in kinds:
		var node := MultiMeshInstance3D.new()
		node.name = "Critters_" + String(kind.id)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = ProceduralMeshes.critter(kind.shape)
		multimesh.instance_count = settings.max_total
		multimesh.visible_instance_count = 0
		node.multimesh = multimesh
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.9
		node.material_override = material
		add_child(node)
		_meshes.append(node)
	_counts.resize(kinds.size())
	EventBus.origin_shifted.connect(_on_origin_shifted)
	if streamer != null:
		streamer.chunks_changed.connect(sync_from_streamer)
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)


func _physics_process(delta: float) -> void:
	_since_tick += delta
	var step := 1.0 / settings.sim_hz
	if _since_tick >= step:
		tick(_since_tick)
		_since_tick = 0.0


func _process(delta: float) -> void:
	advance_hops(delta)
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
	var i := _kind.size() - 1
	while i >= 0:
		if not available.has(_chunk[i]):
			_remove(i)
		i -= 1
	for coord: Vector2i in _rolled.keys():
		if not available.has(coord):
			_rolled.erase(coord)  # rolls again (identically) when it comes back
	for coord in lod0_coords:
		if _rolled.has(coord):
			continue
		_rolled[coord] = true
		var biome := _biome_at(coord)
		for k in kinds.size():
			for xz in CritterPlan.roll(
				coord, terrain.chunk_size, biome, kinds[k], GameState.world_seed
			):
				if _kind.size() >= settings.max_total:
					return
				_spawn(k, coord, xz)


## One decision tick ([param elapsed] seconds since the last one): fleeing, next hops.
func tick(elapsed: float) -> void:
	_tick_count += 1
	var focus := _player()
	var at := focus.global_position if focus != null else Vector3.INF
	if focus != null and _player_previous != Vector3.INF and elapsed > 0.0:
		_player_speed = Vector2(at.x - _player_previous.x, at.z - _player_previous.z).length()
		_player_speed /= elapsed
	_player_previous = at
	for i in _kind.size():
		var here := _position(i)
		var distance := Vector2(here.x - at.x, here.z - at.z).length() if focus != null else INF
		if distance > settings.far_distance and (_tick_count + i) % 3 != 0:
			continue
		var kind := kinds[_kind[i]]
		_timer[i] -= elapsed * (3.0 if distance > settings.far_distance else 1.0)
		if focus != null and _scared(kind, distance):
			if _state[i] != State.FLEE:
				_state[i] = State.FLEE
				_timer[i] = kind.calm_seconds
				_zig[i] = 1.0 if _rng.randf() < 0.5 else -1.0
		if _state[i] == State.FLEE:
			if _timer[i] <= 0.0 and distance > kind.flee_radius:
				_state[i] = State.IDLE
				_home[i] = _to[i]
				_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
			elif _t[i] >= 1.0:
				_flee_hop(i, kind, at)
		elif _t[i] >= 1.0:
			if _state[i] == State.HOP:
				_state[i] = State.IDLE
				_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
			elif _timer[i] <= 0.0:
				_graze_hop(i, kind)


## Moves every hop forward by [param delta] seconds (every frame, for smooth motion).
func advance_hops(delta: float) -> void:
	for i in _kind.size():
		if _t[i] < 1.0:
			_t[i] = minf(1.0, _t[i] + delta / maxf(_hop_seconds[i], 0.01))


## Writes every critter's transform into its kind's MultiMesh.
func draw() -> void:
	_counts.fill(0)
	for i in _kind.size():
		var k := _kind[i]
		var basis := Basis(Vector3.UP, _yaw[i]).scaled(Vector3.ONE * _scale[i])
		_meshes[k].multimesh.set_instance_transform(_counts[k], Transform3D(basis, _position(i)))
		_counts[k] += 1
	for k in kinds.size():
		_meshes[k].multimesh.visible_instance_count = _counts[k]


## Critters alive (all kinds).
func count() -> int:
	return _kind.size()


## Critters alive of kind [param id].
func count_of(id: StringName) -> int:
	var k := kinds.find_custom(func(kind: CritterKind) -> bool: return kind.id == id)
	return _kind.count(k) if k >= 0 else 0


## Where critter [param i] is now (local).
func position_of(i: int) -> Vector3:
	return _position(i)


## State of critter [param i] (a [enum State] value).
func state_of(i: int) -> int:
	return _state[i]


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	var parts := PackedStringArray()
	for kind in kinds:
		parts.append("%s %d" % [kind.id, count_of(kind.id)])
	return PackedStringArray(["critters " + "  ".join(parts)])


func _scared(kind: CritterKind, distance: float) -> bool:
	if distance < kind.startle_radius:
		return true
	return distance < kind.flee_radius and _player_speed > kind.flee_trigger_speed


func _position(i: int) -> Vector3:
	var t := _t[i]
	var p := _from[i].lerp(_to[i], t)
	p.y += 4.0 * _hop_height[i] * t * (1.0 - t)
	return p


func _spawn(k: int, coord: Vector2i, xz: Vector2) -> void:
	var local := GameState.local_position(Vector3(xz.x, 0.0, xz.y))
	local.y = _ground(local)
	if not _dry_and_gentle(local, kinds[k]):
		return
	_kind.append(k)
	_chunk.append(coord)
	_home.append(local)
	_from.append(local)
	_to.append(local)
	_t.append(1.0)
	_hop_seconds.append(kinds[k].graze_hop.z)
	_hop_height.append(0.0)
	_state.append(State.IDLE)
	_timer.append(_rng.randf_range(0.0, kinds[k].idle_seconds.y))
	_yaw.append(_rng.randf() * TAU)
	_scale.append(_rng.randf_range(kinds[k].scale_range.x, kinds[k].scale_range.y))
	_zig.append(1.0)


# Removes critter [param i] by moving the last one into its place. Packed arrays are values in
# GDScript, so each member is handled by name (a loop over them would edit copies).
func _remove(i: int) -> void:
	var last := _kind.size() - 1
	_kind[i] = _kind[last]
	_chunk[i] = _chunk[last]
	_home[i] = _home[last]
	_from[i] = _from[last]
	_to[i] = _to[last]
	_t[i] = _t[last]
	_hop_seconds[i] = _hop_seconds[last]
	_hop_height[i] = _hop_height[last]
	_state[i] = _state[last]
	_timer[i] = _timer[last]
	_yaw[i] = _yaw[last]
	_scale[i] = _scale[last]
	_zig[i] = _zig[last]
	_kind.resize(last)
	_chunk.resize(last)
	_home.resize(last)
	_from.resize(last)
	_to.resize(last)
	_t.resize(last)
	_hop_seconds.resize(last)
	_hop_height.resize(last)
	_state.resize(last)
	_timer.resize(last)
	_yaw.resize(last)
	_scale.resize(last)
	_zig.resize(last)


func _graze_hop(i: int, kind: CritterKind) -> void:
	var angle := _rng.randf() * TAU
	var wanted := _home[i] + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf() * kind.home_radius
	var from := _to[i]
	var offset := Vector3(wanted.x - from.x, 0.0, wanted.z - from.z)
	if offset.length() < 0.05:
		_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
		return
	offset = offset.limit_length(kind.graze_hop.x)
	if _hop(i, from, from + offset, kind.graze_hop, kind):
		_state[i] = State.HOP
	else:
		_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)


func _flee_hop(i: int, kind: CritterKind, threat: Vector3) -> void:
	var from := _to[i]
	var away := Vector3(from.x - threat.x, 0.0, from.z - threat.z)
	if away.length_squared() < 1e-6:
		away = Vector3(sin(_yaw[i]), 0.0, cos(_yaw[i]))
	away = away.normalized()
	_zig[i] = -_zig[i]
	var turn := deg_to_rad(kind.zigzag) * _zig[i] * _rng.randf_range(0.4, 1.0)
	for attempt in 3:  # water or a cliff ahead: try veering off
		var direction := away.rotated(Vector3.UP, turn + attempt * PI / 3.0 * _zig[i])
		if _hop(i, from, from + direction * kind.flee_hop.x, kind.flee_hop, kind):
			return
	_t[i] = 1.0


# Starts a hop from [param from] to [param to] (heights from the ground); false when the
# landing is wet or too steep.
func _hop(i: int, from: Vector3, to: Vector3, hop: Vector3, kind: CritterKind) -> bool:
	to.y = _ground(to)
	if not _dry_and_gentle(to, kind):
		return false
	_from[i] = from
	_to[i] = to
	_t[i] = 0.0
	_hop_seconds[i] = hop.z
	_hop_height[i] = hop.y
	_yaw[i] = atan2(-(to.x - from.x), -(to.z - from.z))
	return true


func _dry_and_gentle(local: Vector3, kind: CritterKind) -> bool:
	if not is_inf(GameState.water_level) and local.y < GameState.water_level + 0.1:
		return false
	var ahead := _ground(local + Vector3(0.5, 0.0, 0.0))
	var side := _ground(local + Vector3(0.0, 0.0, 0.5))
	var slope := atan(Vector2(ahead - local.y, side - local.y).length() / 0.5)
	return slope <= deg_to_rad(kind.max_slope)


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
		_home[i] -= offset
		_from[i] -= offset
		_to[i] -= offset
	if _player_previous != Vector3.INF:
		_player_previous -= offset
