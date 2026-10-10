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
## physics bodies); hops never land in water or on steep ground. Swimmers (ducks) live on the
## water surface instead: they glide, bob, and flee across the water with a splash, never
## leaving it. Amphibians (frogs) live on the banks; scared, they leap into water deep enough
## nearby with a plop, stay under (hidden) for a few seconds and come back up on a bank a few
## metres away, out of the fox's reach. Waders (herons) step slowly through shallow water;
## scared, they fly off ([member CritterKind.flee_hop] is the flight, wings beating in
## [code]shaders/bird.gdshader[/code]) to shallow water farther away. Curlers (hedgehogs) curl
## into a ball instead of fleeing; leapers (fish) stay hidden under the water and now and then
## leap out with a splash. Whistlers (marmots, Phase 17) whistle and dash into their burrow,
## hide there for a while and peek out once the fox has gone. Kinds with
## [member CritterKind.hours] are only out in their hours.
## [br][br]
## Budget: decisions at [member CritterSettings.sim_hz] (critters beyond
## [member CritterSettings.far_distance] every 3rd tick), ≤ 2 height samples per hop (≤ 15 for
## an amphibian, which also looks for water nearby; ≤ 36 when it dives); each frame
## one transform per critter. ≤ 1 ms for 120 critters (measured in tests). Arrays grow only
## when critters spawn.

## Critter states ([constant DIVE]: leaping into the water; [constant UNDER]: under it, hidden;
## [constant LEAP]: a fish out of the water mid-leap; a hidden whistler is [constant UNDER]
## in its burrow).
enum State { IDLE, HOP, FLEE, DIVE, UNDER, LEAP }

## Directions a scared amphibian looks for water in (radians from straight away from the fox,
## nearest first; 12 around).
## Behaviours of dry land (no splashes, no water checks when rolling).
const DRY: Array[StringName] = [&"hopper", &"curler", &"whistler"]
## Behaviours that plop into the water.
const PLOPPING: Array[StringName] = [&"amphibian", &"leaper"]
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
var _meshes: Array[MultiMeshInstance3D] = []
var _splashes: Array[GPUParticles3D] = []
var _next_splash: int = 0
var _time: float = 0.0
var _plop: AudioStreamPlayer3D
var _whistle: AudioStreamPlayer3D
var _out := PackedByteArray()  # per kind: 1 while it is in its hours


func _ready() -> void:
	_rng.seed = 0x5EED
	for kind in kinds:
		var node := MultiMeshInstance3D.new()
		node.name = "Critters_" + String(kind.id)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = ProceduralMeshes.critter(kind.shape)
		# The bird shader reads a wing beat (custom data) and a tint (colour): set before the count.
		multimesh.use_custom_data = kind.behaviour == &"wader"
		multimesh.use_colors = kind.behaviour == &"wader"
		multimesh.instance_count = settings.max_total
		multimesh.visible_instance_count = 0
		node.multimesh = multimesh
		if kind.behaviour == &"wader":  # wings folded while wading, beating in flight
			var wings := ShaderMaterial.new()
			wings.shader = preload("res://shaders/bird.gdshader")
			wings.set_shader_parameter(&"flap_rate", 7.0)
			wings.set_shader_parameter(&"flap_angle", 0.8)
			wings.set_shader_parameter(&"tuck", 0.05)
			wings.set_shader_parameter(&"shoulder", Vector2(0.07, 0.7))
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
	var wet := func(kind: CritterKind) -> bool: return kind.behaviour not in DRY
	if kinds.any(wet):
		for i in 3:
			var splash := MotionEffects.make_emitter(12, 0.8)
			splash.top_level = true
			add_child(splash)
			_splashes.append(splash)
	if kinds.any(func(kind: CritterKind) -> bool: return kind.behaviour in PLOPPING):
		_plop = AudioStreamPlayer3D.new()
		_plop.stream = SynthSounds.plop()
		_plop.bus = &"SFX"
		_plop.unit_size = 3.0
		_plop.top_level = true
		add_child(_plop)
	if kinds.any(func(kind: CritterKind) -> bool: return kind.behaviour == &"whistler"):
		_whistle = AudioStreamPlayer3D.new()
		_whistle.stream = SynthSounds.whistle()
		_whistle.bus = &"SFX"
		_whistle.unit_size = 8.0  # a sharp call that carries across the slope
		_whistle.top_level = true
		add_child(_whistle)
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
	_time += delta
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
			_pending.erase(coord)
	for coord in lod0_coords:
		if _rolled.has(coord):
			continue
		_rolled[coord] = true
		_roll(coord, false)
		_pending.append(coord)


# Spawns the critters of chunk [param coord]: the amphibians (whose banks take many height
# samples to find, ≈ 0.4 ms a chunk) or every other kind.
func _roll(coord: Vector2i, amphibians: bool) -> void:
	var biome := _biome_at(coord)
	for k in kinds.size():
		if (kinds[k].behaviour == &"amphibian") != amphibians:
			continue
		var accept := Callable()
		if kinds[k].behaviour not in DRY:
			accept = _livable.bind(kinds[k])
		# Banks are a narrow strip and deep water is patchy: amphibians and fish look harder
		# for a group centre (a fish's check is one height sample).
		var tries := CritterPlan.CENTRE_TRIES
		if kinds[k].behaviour in PLOPPING:
			tries = 24
		var spots := CritterPlan.roll(
			coord, terrain.chunk_size, biome, kinds[k], GameState.world_seed, accept, tries
		)
		for xz in spots:
			if _kind.size() >= settings.max_total:
				return
			_spawn(k, coord, xz)


## One decision tick ([param elapsed] seconds since the last one): one chunk's amphibians
## spawn (they are rolled after the others, spread over ticks), then fleeing, next hops.
func tick(elapsed: float) -> void:
	_tick_count += 1
	if not _pending.is_empty():
		_roll(_pending.pop_front(), true)
	var focus := _player()
	var at := focus.global_position if focus != null else Vector3.INF
	if focus != null and _player_previous != Vector3.INF and elapsed > 0.0:
		_player_speed = Vector2(at.x - _player_previous.x, at.z - _player_previous.z).length()
		_player_speed /= elapsed
	_player_previous = at
	var hour := GameState.time_of_day() / 60.0
	for k in kinds.size():
		_out[k] = int(kinds[k].is_out(hour))
	for i in _kind.size():
		if _out[_kind[i]] == 0:
			continue  # not its hours: it is away (and keeps its timers)
		var here := _position(i)
		var distance := Vector2(here.x - at.x, here.z - at.z).length() if focus != null else INF
		if distance > settings.far_distance and (_tick_count + i) % 3 != 0:
			continue
		var kind := kinds[_kind[i]]
		_timer[i] -= elapsed * (3.0 if distance > settings.far_distance else 1.0)
		if kind.behaviour == &"amphibian" and _amphibian_tick(i, kind, distance, at):
			continue
		if kind.behaviour == &"leaper":
			_leaper_tick(i, kind)
			continue
		if kind.behaviour == &"whistler" and _whistler_tick(i, kind, distance):
			continue
		if focus != null and _scared(kind, distance):
			if _state[i] != State.FLEE:
				_state[i] = State.FLEE
				_timer[i] = kind.calm_seconds
				_zig[i] = 1.0 if _rng.randf() < 0.5 else -1.0
				if kind.behaviour == &"swimmer":
					_splash(here)
		if _state[i] == State.FLEE:
			if _timer[i] <= 0.0 and distance > kind.flee_radius:
				_state[i] = State.IDLE
				_home[i] = _to[i]
				_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
			elif _t[i] >= 1.0 and kind.behaviour != &"curler":  # a curler stays curled up
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
		if not is_shown(i):
			continue  # under the water, or not its hours
		var basis := Basis(Vector3.UP, _yaw[i])
		match kinds[k].behaviour:
			&"curler":
				if _state[i] == State.FLEE:  # curled into a spiky ball
					basis = basis.scaled(Vector3(0.9, 0.8, 0.62))
			&"leaper":  # nose up leaving the water, nose down diving back
				basis = basis * Basis(Vector3.RIGHT, lerpf(0.9, -0.9, _t[i]))
			&"whistler":  # sits up on its haunches now and then, keeping watch
				if _state[i] == State.IDLE and fmod(_time + _scale[i] * 40.0, 7.0) < 3.0:
					basis = basis.scaled(Vector3(0.85, 1.45, 0.8))
		basis = basis.scaled(Vector3.ONE * _scale[i])
		var at := _position(i)
		if kinds[k].behaviour == &"swimmer":
			at.y += sin(_time * 1.8 + _scale[i] * 40.0) * 0.012  # bobbing on the water
		_meshes[k].multimesh.set_instance_transform(_counts[k], Transform3D(basis, at))
		if kinds[k].behaviour == &"wader":
			var flying := 1.0 if is_flying(i) else 0.0
			_meshes[k].multimesh.set_instance_custom_data(
				_counts[k], Color(flying, _scale[i] * 40.0, 0.0, 0.0)
			)
			_meshes[k].multimesh.set_instance_color(_counts[k], Color.WHITE)
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


## The kind of critter [param i].
func kind_of(i: int) -> CritterKind:
	return kinds[_kind[i]]


## Whether critter [param i] is drawn (not hidden under the water, and in its hours).
func is_shown(i: int) -> bool:
	return _state[i] != State.UNDER and _out[_kind[i]] == 1


## Whether critter [param i] is a wader in flight (not just wading a step away).
func is_flying(i: int) -> bool:
	var kind := kinds[_kind[i]]
	return (
		kind.behaviour == &"wader"
		and _state[i] == State.FLEE
		and _t[i] < 1.0
		and _hop_height[i] >= kind.flee_hop.y * 0.5
	)


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
	if kind.behaviour == &"wader":
		_fly(i, kind, threat)
		return
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


# A fish: hidden until its timer runs out, then a leap; back in the water, hidden again.
func _leaper_tick(i: int, kind: CritterKind) -> void:
	if _state[i] == State.LEAP:
		if _t[i] >= 1.0:
			_plop_at(_to[i])
			_state[i] = State.UNDER
			_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
		return
	if _timer[i] > 0.0:
		return
	var from := Vector3(_to[i].x, GameState.water_level, _to[i].z)
	var home := Vector3(_home[i].x - from.x, 0.0, _home[i].z - from.z)
	for attempt in 4:  # towards home when it has strayed, else anywhere
		var angle := _rng.randf() * TAU
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		if attempt == 0 and home.length() > kind.home_radius:
			direction = home.normalized()
		var to := from + direction * kind.graze_hop.x
		if _ground(to) > GameState.water_level - kind.min_depth:
			continue
		_from[i] = from
		_to[i] = to
		_t[i] = 0.0
		_hop_seconds[i] = kind.graze_hop.z
		_hop_height[i] = kind.graze_hop.y
		_yaw[i] = atan2(-direction.x, -direction.z)
		_state[i] = State.LEAP
		_plop_at(from)
		return
	_timer[i] = 1.0


# Amphibian decisions that differ from a hopper's (true when they replace the rest of the
# tick): landing in the water, coming back up, and diving instead of fleeing on land.
# A marmot: scared, it whistles and dashes home; at its burrow it hides, and peeks out again
# once the fox is beyond [member CritterKind.flee_radius]. True when the tick is handled.
func _whistler_tick(i: int, kind: CritterKind, distance: float) -> bool:
	match _state[i]:
		State.UNDER:
			if _timer[i] <= 0.0:
				if distance < kind.flee_radius:
					_timer[i] = 3.0  # the fox is still about: wait a little longer
				else:
					_state[i] = State.IDLE
					_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
			return true
		State.FLEE:
			if _t[i] >= 1.0:
				_run_home(i, kind)
			return true
	if _scared(kind, distance):
		_whistle_at(_position(i))
		_state[i] = State.FLEE
		_run_home(i, kind)
		return true
	return false


# One dash towards the burrow ([member CritterKind.flee_hop]); there, it disappears inside.
func _run_home(i: int, kind: CritterKind) -> void:
	var from := _to[i]
	var offset := Vector3(_home[i].x - from.x, 0.0, _home[i].z - from.z)
	if offset.length() < 0.3:
		_state[i] = State.UNDER
		_timer[i] = _rng.randf_range(kind.dive_seconds.x, kind.dive_seconds.y)
		return
	var to := from + offset.normalized() * minf(offset.length(), kind.flee_hop.x)
	to.y = _ground(to)
	_from[i] = from
	_to[i] = to
	_t[i] = 0.0
	_hop_seconds[i] = kind.flee_hop.z
	_hop_height[i] = kind.flee_hop.y
	_yaw[i] = atan2(-offset.x, -offset.z)


func _whistle_at(at: Vector3) -> void:
	whistles += 1
	if _whistle != null and _whistle.is_inside_tree():
		_whistle.global_position = at
		_whistle.pitch_scale = _rng.randf_range(0.95, 1.08)
		_whistle.play()


func _amphibian_tick(i: int, kind: CritterKind, distance: float, threat: Vector3) -> bool:
	match _state[i]:
		State.DIVE:
			if _t[i] >= 1.0:
				_plop_at(_to[i])
				_state[i] = State.UNDER
				_timer[i] = _rng.randf_range(kind.dive_seconds.x, kind.dive_seconds.y)
			return true
		State.UNDER:
			if _timer[i] <= 0.0:
				_resurface(i, kind, threat)
			return true
	if _state[i] != State.FLEE and _scared(kind, distance):
		return _dive(i, kind, threat)
	return false


# Leaps into water at least [member CritterKind.min_depth] deep within 2.5 m, preferring
# directions away from [param threat]; false when there is none (it flees on land). ≤ 36
# height samples, only when scared.
func _dive(i: int, kind: CritterKind, threat: Vector3) -> bool:
	if is_inf(GameState.water_level):
		return false
	var from := _to[i]
	var away := Vector3(from.x - threat.x, 0.0, from.z - threat.z)
	if away.length_squared() < 1e-6:
		away = Vector3(sin(_yaw[i]), 0.0, cos(_yaw[i]))
	away = away.normalized()
	for turn: float in DIVE_TURNS:
		var direction := away.rotated(Vector3.UP, turn)
		for reach: float in [0.8, 1.6, 2.5]:
			var spot := from + direction * reach
			if _ground(spot) > GameState.water_level - kind.min_depth:
				continue
			_from[i] = from
			_to[i] = Vector3(spot.x, GameState.water_level, spot.z)
			_t[i] = 0.0
			_hop_seconds[i] = kind.flee_hop.z * maxf(1.0, reach / kind.flee_hop.x)
			_hop_height[i] = kind.flee_hop.y
			_yaw[i] = atan2(-direction.x, -direction.z)
			_state[i] = State.DIVE
			return true
	return false


# Flies off to shallow water about [member CritterKind.flee_hop] [code]x[/code] metres away,
# preferring directions away from [param threat], with a splash as it takes off; when none is
# found it wades a step away instead. ≤ 48 height samples, only when scared.
func _fly(i: int, kind: CritterKind, threat: Vector3) -> void:
	var from := _to[i]
	var away := Vector3(from.x - threat.x, 0.0, from.z - threat.z)
	if away.length_squared() < 1e-6:
		away = Vector3(sin(_yaw[i]), 0.0, cos(_yaw[i]))
	away = away.normalized()
	for turn: float in DIVE_TURNS:
		var direction := away.rotated(Vector3.UP, turn)
		for reach: float in [1.0, 0.7, 1.4, 0.5]:
			if _hop(i, from, from + direction * kind.flee_hop.x * reach, kind.flee_hop, kind):
				_splash(from)
				return
	var step := away * kind.graze_hop.x
	if not _hop(i, from, from + step, kind.graze_hop, kind):
		_t[i] = 1.0


# Comes back up on a bank 1.5–8 m from where it dived, out of the fox's reach
# ([member CritterKind.flee_radius]) if it can, else at least out of startling distance; stays
# under a little longer when no bank is found. ≤ 12 height samples, once per dive.
func _resurface(i: int, kind: CritterKind, threat: Vector3) -> void:
	var under := _to[i]
	for attempt in 12:
		var angle := _rng.randf() * TAU
		var spot := under + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(1.5, 8.0)
		spot.y = _ground(spot)
		if not _valid_spot(spot, kind):
			continue
		var clear := kind.flee_radius if attempt < 8 else kind.startle_radius * 2.0
		if Vector2(spot.x - threat.x, spot.z - threat.z).length() < clear:
			continue
		_from[i] = spot
		_to[i] = spot
		_home[i] = spot
		_t[i] = 1.0
		_state[i] = State.IDLE
		_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
		return
	_timer[i] = 1.0


func _plop_at(at: Vector3) -> void:
	plops += 1
	_splash(at)
	if _plop != null and _plop.is_inside_tree():
		_plop.global_position = at
		_plop.pitch_scale = _rng.randf_range(0.85, 1.2)
		_plop.play()


# Where a critter of [param kind] at [param local] sits: the ground, or the water surface.
func _surface(local: Vector3, kind: CritterKind) -> float:
	if kind.behaviour == &"swimmer" or kind.behaviour == &"leaper":
		return GameState.water_level
	return _ground(local)


func _valid_spot(local: Vector3, kind: CritterKind) -> bool:
	if kind.behaviour in DRY:
		return _dry_and_gentle(local, kind)
	if is_inf(GameState.water_level):
		return false  # every other kind needs water
	match kind.behaviour:
		&"swimmer", &"leaper":
			return _ground(local) <= GameState.water_level - kind.min_depth
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
