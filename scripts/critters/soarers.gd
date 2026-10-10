class_name Soarers
extends Node3D
## Birds of prey you see high above (Phase 17: the golden eagle). While the fox is over their
## biomes by day, one or two appear and soar in wide, slow circles [member
## SoarerSettings.soar_height] above the ground, banking into the turn, their circle drifting
## over their biomes only; now and then one cries. They leave when the fox goes far away, and
## at nightfall.
##
## Like the [BirdFlocks], they live in packed arrays and draw as one [MultiMeshInstance3D]
## (the songbird mesh, scaled and tinted), the wings spread and flexing slightly in
## [code]shaders/bird.gdshader[/code]. The same [method count] / [method position_of] interface
## lets the journal meet them.
## [br][br]
## Budget: decisions at [constant TICK_HZ] (≤ 2 height and 2 biome samples per soarer); per
## frame one transform per soarer (≤ [member SoarerSettings.max_soarers]). The arrays only grow
## when one appears.

## Decisions per second.
const TICK_HZ: float = 4.0

## Where, how many, how they fly.
@export var settings: SoarerSettings
## Terrain (heights and biomes).
@export var terrain: TerrainSettings
## The player (where they appear); defaults to the [code]player[/code] group.
@export var player: Node3D
## Day and night (they leave at night); optional, always day without it.
@export var day_night: DayNightCycle

## Cries so far (tests and tools).
var cries: int = 0

var _sampler: HeightSampler
var _sampler_seed: int = -1
var _rng := RandomNumberGenerator.new()
var _since_tick: float = 0.0
var _cry_timer: float = 0.0
var _multimesh: MultiMesh
var _cry: AudioStreamPlayer3D
# One entry per soarer (absolute circle centre; local positions are derived each frame).
var _centre := PackedVector3Array()
var _drift := PackedVector3Array()
var _angle := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _height := PackedFloat32Array()  # above the ground
var _y := PackedFloat32Array()  # absolute flight height, eased towards the target
var _target_y := PackedFloat32Array()
var _turn := PackedFloat32Array()  # +1 anticlockwise, −1 clockwise


func _ready() -> void:
	_rng.seed = 0xEA61E
	var node := MultiMeshInstance3D.new()
	node.name = "Soarers"
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = ProceduralMeshes.bird()
	_multimesh.instance_count = settings.max_soarers
	_multimesh.visible_instance_count = 0
	node.multimesh = _multimesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/bird.gdshader")
	# Wings always spread (flap 1), flexing only slightly and slowly: gliding, not beating.
	material.set_shader_parameter(&"flap_rate", 1.6)
	material.set_shader_parameter(&"flap_angle", 0.12)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_cry = AudioStreamPlayer3D.new()
	_cry.stream = SynthSounds.cry()
	_cry.bus = &"SFX"
	_cry.unit_size = 40.0  # carries from high above
	_cry.max_distance = settings.cry_radius
	_cry.top_level = true
	add_child(_cry)
	_cry_timer = _rng.randf_range(settings.cry_seconds.x, settings.cry_seconds.y)
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)


func _physics_process(delta: float) -> void:
	_since_tick += delta
	if _since_tick >= 1.0 / TICK_HZ:
		tick(_since_tick)
		_since_tick = 0.0


func _process(delta: float) -> void:
	advance(delta)
	draw()


## One decision tick ([param elapsed] seconds since the last one): soarers appear, drift, pick
## their height, cry and leave.
func tick(elapsed: float) -> void:
	var focus := _player()
	if focus == null:
		return
	var at := GameState.absolute_position(focus.global_position)
	if not is_day():
		_clear()
		return
	for s in range(_centre.size() - 1, -1, -1):
		var offset := Vector2(_centre[s].x - at.x, _centre[s].z - at.z)
		if offset.length() > settings.leave_distance:
			_remove(s)
			continue
		_drift_centre(s, elapsed)
		var here := _absolute_of(s)
		var ground := maxf(_ground(here.x, here.z), _ground(_centre[s].x, _centre[s].z))
		_target_y[s] = ground + _height[s]
	var chance := 1.0 - pow(1.0 - settings.appear_chance, elapsed)
	if _centre.size() < settings.max_soarers and _soared(at.x, at.z) and _rng.randf() < chance:
		_appear(at)
	_cry_timer -= elapsed
	if _cry_timer <= 0.0:
		_cry_timer = _rng.randf_range(settings.cry_seconds.x, settings.cry_seconds.y)
		_cry_near(at)


## Moves every soarer along its circle by [param delta] seconds (every frame).
func advance(delta: float) -> void:
	for s in _centre.size():
		_angle[s] = wrapf(_angle[s] + _turn[s] * settings.speed / _radius[s] * delta, 0.0, TAU)
		_centre[s] += _drift[s] * delta
		_y[s] = lerpf(_y[s], _target_y[s], minf(1.0, delta * 0.3))


## Writes every soarer's transform into the MultiMesh.
func draw() -> void:
	for s in _centre.size():
		var position := GameState.local_position(_absolute_of(s))
		# Facing along the circle (the mesh looks down −Z), banked into the turn.
		var heading := Vector3(-sin(_angle[s]), 0.0, cos(_angle[s])) * _turn[s]
		var basis := Basis.looking_at(heading, Vector3.UP)
		basis = basis * Basis(Vector3.FORWARD, deg_to_rad(settings.bank_degrees) * _turn[s])
		basis = basis.scaled(Vector3.ONE * settings.scale)
		_multimesh.set_instance_transform(s, Transform3D(basis, position))
		_multimesh.set_instance_custom_data(s, Color(1.0, s * 1.7, 0.0, 0.0))
		_multimesh.set_instance_color(s, settings.tint)
	_multimesh.visible_instance_count = _centre.size()


## Whether it is day (soarers are out).
func is_day() -> bool:
	if day_night == null:
		return true
	var hour := GameState.time_of_day() / 60.0
	return DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour) < 0.5


## Soarers in the sky.
func count() -> int:
	return _centre.size()


## Local position of soarer [param s].
func position_of(s: int) -> Vector3:
	return GameState.local_position(_absolute_of(s))


## Height of soarer [param s] above the ground under it (m).
func height_above_ground(s: int) -> float:
	var here := _absolute_of(s)
	return here.y - _ground(here.x, here.z)


## Absolute centre of soarer [param s]'s circle.
func centre_of(s: int) -> Vector3:
	return _centre[s]


## Whether absolute ([param x], [param z]) lies over one of their biomes.
func is_their_sky(x: float, z: float) -> bool:
	return _soared(x, z)


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	return PackedStringArray(["soarers %d  cries %d" % [_centre.size(), cries]])


func _appear(at: Vector3) -> void:
	for attempt in 6:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(settings.appear_distance.x, settings.appear_distance.y)
		var centre := at + Vector3(cos(angle), 0.0, sin(angle)) * distance
		if not _soared(centre.x, centre.z):
			continue
		var height := _rng.randf_range(settings.soar_height.x, settings.soar_height.y)
		var y := _ground(centre.x, centre.z) + height
		centre.y = 0.0
		_centre.append(centre)
		var heading := _rng.randf() * TAU
		_drift.append(Vector3(cos(heading), 0.0, sin(heading)) * settings.drift)
		_angle.append(_rng.randf() * TAU)
		_radius.append(_rng.randf_range(settings.circle_radius.x, settings.circle_radius.y))
		_height.append(height)
		_y.append(y)
		_target_y.append(y)
		_turn.append(1.0 if _rng.randf() < 0.5 else -1.0)
		return


# Keeps the circle over their biomes: a drift that would leave turns back.
func _drift_centre(s: int, elapsed: float) -> void:
	var ahead := _centre[s] + _drift[s] * elapsed * 20.0
	if not _soared(ahead.x, ahead.z):
		_drift[s] = -_drift[s].rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))


func _cry_near(at: Vector3) -> void:
	for s in _centre.size():
		var here := _absolute_of(s)
		if here.distance_to(at) <= settings.cry_radius:
			cries += 1
			if _cry.is_inside_tree():
				_cry.global_position = GameState.local_position(here)
				_cry.pitch_scale = _rng.randf_range(0.92, 1.06)
				_cry.play()
			return


func _absolute_of(s: int) -> Vector3:
	var c := _centre[s]
	return Vector3(c.x + cos(_angle[s]) * _radius[s], _y[s], c.z + sin(_angle[s]) * _radius[s])


func _remove(s: int) -> void:
	_centre.remove_at(s)
	_drift.remove_at(s)
	_angle.remove_at(s)
	_radius.remove_at(s)
	_height.remove_at(s)
	_y.remove_at(s)
	_target_y.remove_at(s)
	_turn.remove_at(s)


func _clear() -> void:
	for s in range(_centre.size() - 1, -1, -1):
		_remove(s)


func _soared(x: float, z: float) -> bool:
	_sampler_check()
	var resolver := _sampler.resolver()
	return resolver != null and settings.biomes.has(resolver.dominant_at(x, z).id)


func _ground(x: float, z: float) -> float:
	_sampler_check()
	return _sampler.height_at(x, z)


func _sampler_check() -> void:
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
