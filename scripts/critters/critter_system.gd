class_name CritterSystem
extends CritterCore
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
## hide there for a while and peek out once the fox has gone. Otters (Phase 19) glide on the
## water, dive and come up elsewhere, float on their backs and climb out on the banks to roll
## about; curious, they watch the fox, keeping their distance, and startled they dive. A family
## lives at each otter den of the island treasures. Kinds with [member CritterKind.hours] are
## only out in their hours.
## [br][br]
## Budget: decisions at [member CritterSettings.sim_hz] (critters beyond
## [member CritterSettings.far_distance] every 3rd tick), ≤ 2 height samples per hop (≤ 15 for
## an amphibian, which also looks for water nearby; ≤ 36 when it dives; ≤ 24 for an otter's
## choice, ≤ 240 once to find a den family's water); each frame
## one transform per critter. ≤ 1 ms for 120 critters (measured in tests). Arrays grow only
## when critters spawn.


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
	var calls := func(kind: CritterKind) -> bool:
		return kind.behaviour == &"whistler" and kind.alarm_call
	if kinds.any(calls):
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
		if not amphibians and kinds[k].den_family != Vector2i.ZERO:
			_den_families(k, coord)


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
		if kind.behaviour == &"otter":
			_otter_tick(i, kind, distance, at)
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
		var basis := basis_of(i)
		var at := _position(i)
		if kinds[k].behaviour == &"swimmer":
			at.y += sin(_time * 1.8 + _scale[i] * 40.0) * 0.012  # bobbing on the water
		elif kinds[k].behaviour == &"otter" and is_swimming(i):
			# Low in the water; on its back the flipped body hangs below its origin, so it rises.
			at.y += (0.17 if _pose[i] == Pose.ON_BACK else -0.08) * _scale[i]
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


## Orientation, pose and size of critter [param i] as drawn now.
func basis_of(i: int) -> Basis:
	var kind := kinds[_kind[i]]
	var basis := Basis(Vector3.UP, _yaw[i])
	match kind.behaviour:
		&"curler":
			if _state[i] == State.FLEE:  # curled into a spiky ball
				basis = basis.scaled(Vector3(0.9, 0.8, 0.62))
		&"leaper":  # nose up leaving the water, nose down diving back
			basis = basis * Basis(Vector3.RIGHT, lerpf(0.9, -0.9, _t[i]))
		&"whistler":  # sits up on its haunches now and then, keeping watch
			var watching := fmod(_time + _scale[i] * 40.0, 7.0) < 3.0
			if kind.sits_up and _state[i] == State.IDLE and watching:
				basis = basis.scaled(Vector3(0.85, 1.45, 0.8))
		&"otter":
			match _pose[i]:
				Pose.ON_BACK:  # belly up, paws to the sky
					basis = basis * Basis(Vector3.BACK, PI)
				Pose.ROLLING:  # rolling from side to side on the bank
					basis = basis * Basis(Vector3.BACK, sin(_time * 3.0 + _scale[i] * 40.0) * 1.3)
	return basis.scaled(Vector3.ONE * _scale[i])


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


## Pose of critter [param i] (a [enum Pose] value; otters).
func pose_of(i: int) -> int:
	return _pose[i]


## Whether critter [param i] is in the water (an otter swimming, or under it).
func is_swimming(i: int) -> bool:
	return _to[i].y <= GameState.water_level + 0.01 and not is_inf(GameState.water_level)


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
		if kind.alarm_call:
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


# An otter's tick: under water it waits, then comes up; startled it dives; with the fox near
# (not rushing) it watches it, swimming back to keep its distance; otherwise, between moves, it
# picks something to do: swim about, dive, float on its back, climb out on a bank to roll,
# or slide back into the water.
func _otter_tick(i: int, kind: CritterKind, distance: float, threat: Vector3) -> void:
	match _state[i]:
		State.DIVE:
			if _t[i] >= 1.0:
				_otter_under(i, kind)
			return
		State.UNDER:
			if _timer[i] <= 0.0:
				_otter_surface(i, kind, threat)
			return
	var swimming := is_swimming(i)
	if _scared(kind, distance):
		_pose[i] = Pose.NONE
		if swimming:
			_otter_under(i, kind)
		elif not _dive(i, kind, threat):  # into the water nearby, else a dash on land
			_flee_hop(i, kind, threat)
		return
	if distance < kind.curious_radius and _t[i] >= 1.0:
		_otter_watch(i, kind, distance, threat, swimming)
	elif _t[i] >= 1.0:
		_otter_next(i, kind, swimming)


# Faces the fox; closer than [member CritterKind.keep_distance] it backs off (swimming away, or
# sliding into the water from a bank).
func _otter_watch(
	i: int, kind: CritterKind, distance: float, threat: Vector3, swimming: bool
) -> void:
	_pose[i] = Pose.NONE
	var here := _to[i]
	_yaw[i] = atan2(-(threat.x - here.x), -(threat.z - here.z))  # face the fox
	if distance < kind.keep_distance:
		var away := Vector3(here.x - threat.x, 0.0, here.z - threat.z).normalized()
		if swimming:
			_otter_swim(i, kind, here + away * kind.graze_hop.x)
		else:
			_otter_slide(i, kind)


# Between moves: a move just ended, it waits, or it picks something to do.
func _otter_next(i: int, kind: CritterKind, swimming: bool) -> void:
	if _state[i] == State.HOP:
		_state[i] = State.IDLE
		_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
		if not is_swimming(i):
			_pose[i] = Pose.ROLLING
		return
	if _timer[i] > 0.0:
		return
	_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
	var roll := _rng.randf()
	if not swimming:
		_pose[i] = Pose.ROLLING
		if roll < 0.5:
			_otter_slide(i, kind)
		return
	_pose[i] = Pose.NONE
	if roll < 0.5:
		var angle := _rng.randf() * TAU
		var spot := (
			_home[i] + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf() * kind.home_radius
		)
		_otter_swim(i, kind, spot)
	elif roll < 0.68:
		_plop_at(_to[i])
		_otter_under(i, kind)
	elif roll < 0.86:
		_pose[i] = Pose.ON_BACK
		_timer[i] *= 2.0
	else:
		_otter_climb_out(i, kind)


# Glides towards [param target] on the water, at most [member CritterKind.graze_hop] x metres;
# stays put when the water there is too shallow. 1 height sample.
func _otter_swim(i: int, kind: CritterKind, target: Vector3) -> void:
	var from := _to[i]
	var offset := Vector3(target.x - from.x, 0.0, target.z - from.z).limit_length(kind.graze_hop.x)
	var to := Vector3(from.x + offset.x, GameState.water_level, from.z + offset.z)
	if offset.length() < 0.05 or not _deep(to, kind):
		return
	_from[i] = from
	_to[i] = to
	_t[i] = 0.0
	_hop_seconds[i] = kind.graze_hop.z
	_hop_height[i] = 0.0
	_yaw[i] = atan2(-offset.x, -offset.z)
	_state[i] = State.HOP


# Hidden under the water for [member CritterKind.dive_seconds].
func _otter_under(i: int, kind: CritterKind) -> void:
	_pose[i] = Pose.NONE
	_from[i] = _to[i]
	_t[i] = 1.0
	_state[i] = State.UNDER
	_timer[i] = _rng.randf_range(kind.dive_seconds.x, kind.dive_seconds.y)


# Comes up 3–10 m from where it went under (towards home when it has strayed), beyond the fox's
# reach ([member CritterKind.flee_radius]) if it can. ≤ 12 height samples.
func _otter_surface(i: int, kind: CritterKind, threat: Vector3) -> void:
	var under := _to[i]
	var homeward := Vector3(_home[i].x - under.x, 0.0, _home[i].z - under.z)
	for attempt in 12:
		var angle := _rng.randf() * TAU
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		if attempt < 4 and homeward.length() > kind.home_radius:
			direction = homeward.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
		var spot := under + direction * _rng.randf_range(3.0, 10.0)
		spot.y = GameState.water_level
		if not _deep(spot, kind):
			continue
		var clear := kind.flee_radius if attempt < 8 else kind.startle_radius
		if Vector2(spot.x - threat.x, spot.z - threat.z).length() < clear:
			continue
		_from[i] = spot
		_to[i] = spot
		_t[i] = 1.0
		_state[i] = State.IDLE
		_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
		_splash(spot)
		return
	_timer[i] = 1.0


# Swims to the nearest shore along 8 rays (2 m steps, up to 20 m) and climbs out where the
# bank is low and gentle; it rolls about there. ≤ 8 × 10 + 2 height samples.
func _otter_climb_out(i: int, kind: CritterKind) -> void:
	var from := _to[i]
	var first := _rng.randi() % 8
	for d in 8:
		var angle := (first + d) * TAU / 8.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		for step in range(1, 11):
			var spot := from + direction * step * 2.0
			spot.y = _ground(spot)
			var height := spot.y - GameState.water_level
			if height < 0.02:
				continue  # still water
			if height > kind.bank_height or not _gentle(spot, kind):
				break  # a steep shore this way
			_from[i] = from
			_to[i] = spot
			_t[i] = 0.0
			_hop_seconds[i] = kind.graze_hop.z * step  # swimming there
			_hop_height[i] = 0.0
			_yaw[i] = atan2(-direction.x, -direction.z)
			_state[i] = State.HOP
			return


# Slides off the bank into water deep enough within 3 m (≤ 12 height samples), with a plop.
func _otter_slide(i: int, kind: CritterKind) -> void:
	var from := _to[i]
	for d in 12:
		var angle := d * TAU / 12.0
		for reach: float in [1.5, 3.0]:
			var spot := from + Vector3(cos(angle), 0.0, sin(angle)) * reach
			spot.y = GameState.water_level
			if not _deep(spot, kind):
				continue
			_pose[i] = Pose.NONE
			_from[i] = from
			_to[i] = spot
			_t[i] = 0.0
			_hop_seconds[i] = kind.flee_hop.z
			_hop_height[i] = kind.graze_hop.y
			_yaw[i] = atan2(-(spot.x - from.x), -(spot.z - from.z))
			_state[i] = State.HOP
			_plop_at(spot)
			return


# The family of each otter den (an island treasure) in chunk [param coord]: in the water
# nearest the den, found on rings round it (≤ 16 × 16 height samples, once per den).
func _den_families(k: int, coord: Vector2i) -> void:
	if terrain.islands == null or terrain.biomes == null:
		return
	var kind := kinds[k]
	var size := terrain.chunk_size
	var rect := Rect2(Vector2(coord) * size, Vector2.ONE * size)
	var centre := rect.get_center()
	var dens := IslandPlan.near(
		centre.x,
		centre.y,
		size,
		terrain.islands,
		_height_sampler(),
		GameState.world_seed,
		terrain.sea_level
	)
	for den in dens:
		if (
			den.kind != IslandPlan.Treasure.OTTER_DEN
			or not rect.has_point(Vector2(den.centre.x, den.centre.z))
		):
			continue
		var water := _water_round(den.centre, kind)
		if water == Vector2.INF:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = den.seed
		for n in rng.randi_range(kind.den_family.x, kind.den_family.y):
			if _kind.size() >= settings.max_total:
				return
			var spot := water + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * 2.0
			_spawn(k, coord, spot)


# The nearest water deep enough for [param kind] round absolute [param at] (absolute X, Z).
func _water_round(at: Vector3, kind: CritterKind) -> Vector2:
	var sampler := _height_sampler()
	var water := terrain.sea_level - kind.min_depth
	for ring in range(1, 17):
		for d in 16:
			var spot := Vector2(at.x, at.z) + Vector2.from_angle(d * TAU / 16.0) * ring * 5.0
			if sampler.height_at(spot.x, spot.y) <= water - 0.3:  # a little off the shore
				return spot
	return Vector2.INF
