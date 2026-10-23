class_name CritterCore
extends Node3D
## What every critter of the [CritterSystem] is made of: its kinds and settings, the packed
## arrays holding one entry per critter (struct of arrays; removal swaps with the last), and the
## low-level moves and checks the behaviours share: hops, splashes and plops, where a kind may
## stand (ground, banks, water deep enough) and the ground height (from the [HeightSampler]).
## The behaviours themselves (and the public queries) live in [CritterSystem], which extends it.

## Critter states ([constant DIVE]: leaping into the water; [constant UNDER]: under it, hidden;
## [constant LEAP]: a fish out of the water mid-leap; a hidden whistler is [constant UNDER]
## in its burrow).
enum State { IDLE, HOP, FLEE, DIVE, UNDER, LEAP }

## Poses an otter or a beaver can hold ([method CritterSystem.pose_of]; CARRYING: a beaver with
## a stick in its teeth).
enum Pose { NONE, ON_BACK, ROLLING, CARRYING }

## Behaviours of dry land (no splashes, no water checks when rolling).
const DRY: Array[StringName] = [&"hopper", &"curler", &"whistler"]
## Behaviours that plop into the water.
const PLOPPING: Array[StringName] = [&"amphibian", &"leaper", &"otter", &"beaver"]
## How far apart the two of a pair glide (m).
const PAIR_GAP: float = 1.4
## Behaviours that swim at the surface over water and walk on the banks.
const SWIM_AND_WALK: Array[StringName] = [&"otter", &"beaver"]
## Directions a scared amphibian looks for water in (radians from straight away from the fox,
## nearest first; 12 around).
const DIVE_TURNS: Array[float] = [
	0.0, 0.52, -0.52, 1.05, -1.05, 1.57, -1.57, 2.09, -2.09, 2.62, -2.62, PI
]

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

## Splashes made so far (tests and tools).
var splashes: int = 0
## Plops (an amphibian reaching the water) so far (tests and tools).
var plops: int = 0
## Alarm whistles (a scared marmot) so far (tests and tools).
var whistles: int = 0
## Tail slaps (a startled beaver) so far (tests and tools).
var slaps: int = 0

var _sampler: HeightSampler
var _sampler_seed: int = -1
var _resolver: BiomeResolver
var _rng := RandomNumberGenerator.new()
var _rolled: Dictionary[Vector2i, bool] = {}
var _pending: Array[Vector2i] = []  # chunks whose amphibians are still to roll (1 per tick)
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
var _pose := PackedByteArray()
var _meshes: Array[MultiMeshInstance3D] = []
var _splashes: Array[GPUParticles3D] = []
var _next_splash: int = 0
var _time: float = 0.0
var _plop: AudioStreamPlayer3D
var _whistle: AudioStreamPlayer3D
var _slap: AudioStreamPlayer3D
var _lodges: BeaverLodges
var _sticks: MultiMeshInstance3D
var _out := PackedByteArray()  # per kind: 1 while it is in its hours


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
	local.y = _surface(local, kinds[k])
	if not _valid_spot(local, kinds[k]):
		return
	_kind.append(k)
	_chunk.append(coord)
	_home.append(local)
	_from.append(local)
	_to.append(local)
	_t.append(1.0)
	_hop_seconds.append(kinds[k].graze_hop.z)
	_hop_height.append(0.0)
	_state.append(State.UNDER if kinds[k].behaviour == &"leaper" else State.IDLE)
	_timer.append(_rng.randf_range(0.0, kinds[k].idle_seconds.y))
	_yaw.append(_rng.randf() * TAU)
	_scale.append(_rng.randf_range(kinds[k].scale_range.x, kinds[k].scale_range.y))
	_zig.append(1.0)
	_pose.append(Pose.NONE)


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
	_pose[i] = _pose[last]
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
	_pose.resize(last)


# Starts a hop from [param from] to [param to] (heights from the ground); false when the
# landing is wet or too steep.
func _hop(i: int, from: Vector3, to: Vector3, hop: Vector3, kind: CritterKind) -> bool:
	to.y = _surface(to, kind)
	if not _valid_spot(to, kind):
		return false
	_from[i] = from
	_to[i] = to
	_t[i] = 0.0
	_hop_seconds[i] = hop.z
	_hop_height[i] = hop.y
	_yaw[i] = atan2(-(to.x - from.x), -(to.z - from.z))
	return true


func _whistle_at(at: Vector3) -> void:
	whistles += 1
	if _whistle != null and _whistle.is_inside_tree():
		_whistle.global_position = at
		_whistle.pitch_scale = _rng.randf_range(0.95, 1.08)
		_whistle.play()


# Whether the water at [param local] is at least [member CritterKind.min_depth] deep.
func _deep(local: Vector3, kind: CritterKind) -> bool:
	return _ground(local) <= GameState.water_level - kind.min_depth


func _plop_at(at: Vector3) -> void:
	plops += 1
	_splash(at)
	if _plop != null and _plop.is_inside_tree():
		_plop.global_position = at
		_plop.pitch_scale = _rng.randf_range(0.85, 1.2)
		_plop.play()


# A spot about [constant PAIR_GAP] from the partner of critter [param i] (the nearest of its kind
# in its chunk; swans keep in pairs), or [param wanted] when it has none. ≤ the chunk's critters.
func _beside_partner(i: int, wanted: Vector3, angle: float) -> Vector3:
	var partner := -1
	var best := INF
	for j in _kind.size():
		if j == i or _kind[j] != _kind[i] or _chunk[j] != _chunk[i]:
			continue
		var d := _to[j].distance_squared_to(_to[i])
		if d < best:
			best = d
			partner = j
	if partner < 0:
		return wanted
	return _to[partner] + Vector3(cos(angle), 0.0, sin(angle)) * PAIR_GAP


# Where a critter of [param kind] at [param local] sits: the ground, or the water surface.
func _surface(local: Vector3, kind: CritterKind) -> float:
	if kind.behaviour == &"swimmer" or kind.behaviour == &"leaper":
		return GameState.water_level
	var ground := _ground(local)
	if kind.behaviour in SWIM_AND_WALK and ground < GameState.water_level:
		return GameState.water_level  # swimming
	return ground


func _valid_spot(local: Vector3, kind: CritterKind) -> bool:
	if kind.behaviour in DRY:
		return _dry_and_gentle(local, kind)
	if is_inf(GameState.water_level):
		return false  # every other kind needs water
	match kind.behaviour:
		&"swimmer", &"leaper", &"otter":
			return _deep(local, kind)
		&"beaver":
			return _deep(local, kind) or _on_a_bank(local, kind)
		&"wader":
			return _wading(local, kind)
	return _on_a_bank(local, kind)


# Standing in shallow water ([member CritterKind.wade_depth]) on a gentle bed.
func _wading(local: Vector3, kind: CritterKind) -> bool:
	var depth := GameState.water_level - local.y
	return depth >= kind.wade_depth.x and depth <= kind.wade_depth.y and _gentle(local, kind)


# A bank: from just under the waterline up to [member CritterKind.bank_height], gentle, with
# water to dive into nearby.
func _on_a_bank(local: Vector3, kind: CritterKind) -> bool:
	var height := local.y - GameState.water_level
	if height < -0.05 or height > kind.bank_height or not _gentle(local, kind):
		return false
	return _water_near(local, kind)


# Whether water deep enough to dive into ([member CritterKind.min_depth]) is within 2 m of
# [param local] (6 directions × 2 distances: ≤ 12 height samples, stopping at the first).
func _water_near(local: Vector3, kind: CritterKind) -> bool:
	for reach: float in [1.0, 2.0]:
		for d in 6:
			var angle := d * TAU / 6.0 + reach
			var spot := local + Vector3(cos(angle), 0.0, sin(angle)) * reach
			if _ground(spot) <= GameState.water_level - kind.min_depth:
				return true
	return false


# Whether absolute X/Z [param xz] is a place [param kind] lives (water deep enough for a
# swimmer, a bank for an amphibian): group centres.
func _livable(xz: Vector2, kind: CritterKind) -> bool:
	var local := GameState.local_position(Vector3(xz.x, 0.0, xz.y))
	local.y = _surface(local, kind)
	return _valid_spot(local, kind)


func _splash(at: Vector3) -> void:
	splashes += 1
	if _splashes.is_empty() or (Settings.quality != null and not Settings.quality.motion_effects):
		return
	var emitter := _splashes[_next_splash]
	_next_splash = (_next_splash + 1) % _splashes.size()
	emitter.global_position = at + Vector3.UP * 0.05
	(emitter.process_material as ParticleProcessMaterial).color = Color(0.85, 0.93, 1.0, 0.7)
	emitter.restart()
	emitter.emitting = true


func _dry_and_gentle(local: Vector3, kind: CritterKind) -> bool:
	if not is_inf(GameState.water_level) and local.y < GameState.water_level + 0.1:
		return false
	if kind.behaviour == &"whistler" and GameState.absolute_position(local).y > GameState.snow_line:
		return false  # marmots dig their burrows below the snow
	return _gentle(local, kind)


func _gentle(local: Vector3, kind: CritterKind) -> bool:
	var ahead := _ground(local + Vector3(0.5, 0.0, 0.0))
	var side := _ground(local + Vector3(0.0, 0.0, 0.5))
	var slope := atan(Vector2(ahead - local.y, side - local.y).length() / 0.5)
	return slope <= deg_to_rad(kind.max_slope)


func _ground(local: Vector3) -> float:
	var at := GameState.absolute_position(local)
	return _height_sampler().height_at(at.x, at.z)


func _height_sampler() -> HeightSampler:
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed
		_resolver = null
	return _sampler


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
