class_name FarmLife
extends Node
## The animals of the hamlets: sheep, pigs and cows ([FarmAnimalKind]) in each stable's pen, and
## chickens pecking about the yard. They are built with their hamlet ([signal
## HamletDirector.hamlet_built]) as children of its root, so they follow it (floating origin) and
## go with it when it is freed.
## [br]- Penned animals stand a while, then move to another spot of the pen: cows walk, sheep
##   and pigs (whose models only have a hop) go in little hops.
## [br]- Chickens (a [CritterKind] for their look and hours) peck in short hops around their
##   spot; when the fox comes running (or bumps into them) they scatter and later come back.
##   They are indoors at night.
## [br][br]
## Budget: a few dozen animals at most, one small update each per frame; heights sampled only
## when one picks a new spot.

## Animal states.
enum State { IDLE, MOVE, SCATTER }

## Least distance between two penned animals' spots (m).
const ROOM: float = 1.6

## The hamlets they live in.
@export var director: HamletDirector
## Kinds of penned animals.
@export var kinds: Array[FarmAnimalKind] = []
## The chickens (their [member CritterKind.hours], scale, hops and fleeing).
@export var chicken: CritterKind
## Animals per pen, and chickens per hamlet (min, max).
@export var per_pen: Vector2i = Vector2i(3, 5)
@export var chickens: Vector2i = Vector2i(3, 6)
## The player (scares chickens); defaults to the [code]player[/code] group.
@export var player: Node3D

var _node: Array[Node3D] = []
var _anim: Array[AnimationPlayer] = []
var _kind := PackedInt32Array()  # index in kinds, or -1 for a chicken
var _cell: Array[Vector2i] = []
var _layout: Array[HamletLayout] = []
var _home := PackedVector3Array()  # local to the hamlet's root
var _radius := PackedFloat32Array()
var _from := PackedVector3Array()
var _to := PackedVector3Array()
var _t := PackedFloat32Array()
var _seconds := PackedFloat32Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _sampler: HeightSampler
var _sampler_seed: int = -1
var _player_previous := Vector3.INF
var _chicken_mesh: Mesh
var _chicken_material: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 0xFA2
	if chicken != null:
		_chicken_mesh = ProceduralMeshes.critter(chicken.shape)
		_chicken_material = StandardMaterial3D.new()
		_chicken_material.vertex_color_use_as_albedo = true
		_chicken_material.roughness = 0.9
	if director != null:
		director.hamlet_built.connect(populate)
		director.hamlet_freed.connect(forget)


func _process(delta: float) -> void:
	step(delta)


## Puts animals in the pen and chickens in the yard of [param layout] (seeded per hamlet).
func populate(layout: HamletLayout, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layout.cell) ^ 0xFA2
	if layout.pen != Vector3.INF and not kinds.is_empty():
		for n in rng.randi_range(per_pen.x, per_pen.y):
			var k := _pick(rng)
			var home := layout.pen - layout.centre
			var radius := maxf(layout.pen_half - 1.2, 0.5)
			var at := home
			for attempt in 8:  # a free spot (they don't stand inside one another)
				var angle := rng.randf() * TAU
				at = home + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf() * radius
				if not _crowded(layout.cell, -1, at):
					break
			_add(k, layout, home, radius, at, _model(kinds[k], root))
	if chicken != null and layout.size() > 1:
		var house := layout.positions[1 + rng.randi() % mini(3, layout.size() - 1)]
		var toward := (layout.centre - house).normalized()
		var spot := house - layout.centre + toward * (layout.radii[1] + 2.5)
		for n in rng.randi_range(chickens.x, chickens.y):
			var angle := rng.randf() * TAU
			var at := spot + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf() * 3.0
			_add(-1, layout, spot, 4.0, at, _chicken_node(root))


## Drops the animals of the hamlet of [param cell] (their nodes go with its root).
func forget(cell: Vector2i) -> void:
	for i in range(_node.size() - 1, -1, -1):
		if _cell[i] == cell:
			_remove(i)


## Advances every animal by [param delta] seconds.
func step(delta: float) -> void:
	var focus := _player()
	var speed := 0.0
	if focus != null:
		if _player_previous != Vector3.INF and delta > 0.0:
			var moved := focus.global_position - _player_previous
			speed = Vector2(moved.x, moved.z).length() / delta
		_player_previous = focus.global_position
	var hour := GameState.time_of_day() / 60.0
	for i in _node.size():
		if not is_instance_valid(_node[i]):
			continue
		if _kind[i] < 0:
			_node[i].visible = chicken.is_out(hour)
			if not _node[i].visible:
				continue
		_timer[i] -= delta
		if _kind[i] < 0 and focus != null:
			_maybe_scatter(i, focus.global_position, speed)
		if _t[i] < 1.0:
			_t[i] = minf(1.0, _t[i] + delta / maxf(_seconds[i], 0.01))
			var p := _from[i].lerp(_to[i], _t[i])
			if _kind[i] < 0:
				p.y += 4.0 * 0.08 * _t[i] * (1.0 - _t[i])  # a chicken's hop
			_node[i].position = p
			if _t[i] >= 1.0:
				_arrive(i)
		elif _timer[i] <= 0.0:
			_wander(i)


## Animals alive (penned and chickens).
func count() -> int:
	return _node.size()


## Where animal [param i] is (global).
func position_of(i: int) -> Vector3:
	return _node[i].global_position


## Its kind: a [FarmAnimalKind], or the chickens' [CritterKind].
func kind_of(i: int) -> Resource:
	return chicken if _kind[i] < 0 else kinds[_kind[i]]


## Whether animal [param i] is out (chickens are indoors at night).
func is_shown(i: int) -> bool:
	return is_instance_valid(_node[i]) and _node[i].visible


## State of animal [param i] (a [enum State] value).
func state_of(i: int) -> int:
	return _state[i]


## The centre and radius of the area animal [param i] keeps to (global centre).
func home_of(i: int) -> Vector4:
	var root := _node[i].get_parent() as Node3D
	var centre := root.global_position + _home[i]
	return Vector4(centre.x, centre.y, centre.z, _radius[i])


func _pick(rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for kind in kinds:
		total += kind.weight
	var roll := rng.randf() * total
	for k in kinds.size():
		roll -= kinds[k].weight
		if roll <= 0.0:
			return k
	return kinds.size() - 1


func _add(
	k: int, layout: HamletLayout, home: Vector3, radius: float, at: Vector3, node: Node3D
) -> void:
	at.y = _ground(layout, at)
	node.position = at
	node.rotation.y = _rng.randf() * TAU
	_node.append(node)
	_anim.append(
		node.find_children("*", "AnimationPlayer", true, false).front() if k >= 0 else null
	)
	_kind.append(k)
	_cell.append(layout.cell)
	_layout.append(layout)
	_home.append(home)
	_radius.append(radius)
	_from.append(at)
	_to.append(at)
	_t.append(1.0)
	_seconds.append(1.0)
	_state.append(State.IDLE)
	_timer.append(_rng.randf_range(0.0, 3.0))
	_play(_node.size() - 1, true)


func _model(kind: FarmAnimalKind, root: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = String(kind.id)
	var model: Node3D = kind.scene.instantiate()
	model.scale = Vector3.ONE * kind.model_scale
	model.rotation.y = deg_to_rad(kind.yaw_offset)
	holder.add_child(model)
	root.add_child(holder)
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false).front()
	for clip: String in [kind.idle_clip] + ([] if kind.hops else [kind.move_clip]):
		if player != null and player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR  # (shared: once is enough)
	return holder


func _chicken_node(root: Node3D) -> Node3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "chicken"
	mesh.mesh = _chicken_mesh
	mesh.material_override = _chicken_material
	mesh.scale = Vector3.ONE * _rng.randf_range(chicken.scale_range.x, chicken.scale_range.y)
	root.add_child(mesh)
	return mesh


# Picks a new spot near home and sets off (a walk, a hop or a chicken's hop).
func _wander(i: int) -> void:
	var from := _node[i].position
	for attempt in 6:  # a step towards a spot of home where no other penned animal stands
		var angle := _rng.randf() * TAU
		var spot := _home[i] + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf() * _radius[i]
		var offset := Vector3(spot.x - from.x, 0.0, spot.z - from.z)
		var seconds: float
		if _kind[i] < 0:
			offset = offset.limit_length(chicken.graze_hop.x)
			seconds = chicken.graze_hop.z
		else:
			var kind := kinds[_kind[i]]
			if kind.hops:
				offset = offset.limit_length(kind.move)
				seconds = _anim[i].get_animation(kind.move_clip).length if _anim[i] != null else 1.0
			else:
				seconds = offset.length() / kind.move
		if offset.length() < 0.05:
			continue
		if _kind[i] >= 0 and _crowded(_cell[i], i, from + offset):
			continue  # where it would land (a hop stops short of the spot) is taken
		_go(i, from, from + offset, seconds, State.MOVE)
		return
	_timer[i] = 1.0


# Whether a penned animal (other than [param i]) of the hamlet of [param cell] stands or is
# heading within [constant ROOM] of [param spot].
func _crowded(cell: Vector2i, i: int, spot: Vector3) -> bool:
	for j in _node.size():
		if j == i or _kind[j] < 0 or _cell[j] != cell:
			continue
		for other: Vector3 in [_to[j], _node[j].position]:
			if Vector2(other.x - spot.x, other.z - spot.z).length() < ROOM:
				return true
	return false


func _go(i: int, from: Vector3, to: Vector3, seconds: float, state: int) -> void:
	to.y = _ground(_layout[i], to)
	_from[i] = from
	_to[i] = to
	_t[i] = 0.0
	_seconds[i] = seconds
	_state[i] = state
	_node[i].rotation.y = atan2(-(to.x - from.x), -(to.z - from.z))
	_play(i, false)


func _arrive(i: int) -> void:
	_state[i] = State.IDLE
	if _kind[i] < 0:
		_timer[i] = _rng.randf_range(chicken.idle_seconds.x, chicken.idle_seconds.y)
	else:
		var kind := kinds[_kind[i]]
		_timer[i] = _rng.randf_range(kind.idle_seconds.x, kind.idle_seconds.y)
	_play(i, true)


# A chicken near a running fox (or bumped into) scatters: quick hops away, then it calms down.
func _maybe_scatter(i: int, fox: Vector3, speed: float) -> void:
	var here := _node[i].global_position
	var distance := Vector2(here.x - fox.x, here.z - fox.z).length()
	var scared := (
		distance < chicken.startle_radius
		or (distance < chicken.flee_radius and speed > chicken.flee_trigger_speed)
	)
	if not scared or (_state[i] == State.SCATTER and _t[i] < 1.0):
		return
	var away := Vector3(here.x - fox.x, 0.0, here.z - fox.z)
	away = away.normalized() if away.length_squared() > 1e-6 else Vector3.RIGHT
	away = away.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	var from := _node[i].position
	_go(i, from, from + away * chicken.flee_hop.x, chicken.flee_hop.z, State.SCATTER)
	_timer[i] = chicken.calm_seconds


func _play(i: int, idle: bool) -> void:
	if _anim[i] == null:
		return
	var kind := kinds[_kind[i]]
	var clip := kind.idle_clip if idle else kind.move_clip
	if _anim[i].has_animation(clip):
		_anim[i].play(clip)


func _ground(layout: HamletLayout, local: Vector3) -> float:
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(director.terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed
	return (
		_sampler.height_at(layout.centre.x + local.x, layout.centre.z + local.z) - layout.centre.y
	)


func _remove(i: int) -> void:
	_node.remove_at(i)
	_anim.remove_at(i)
	_kind.remove_at(i)
	_cell.remove_at(i)
	_layout.remove_at(i)
	_home.remove_at(i)
	_radius.remove_at(i)
	_from.remove_at(i)
	_to.remove_at(i)
	_t.remove_at(i)
	_seconds.remove_at(i)
	_state.remove_at(i)
	_timer.remove_at(i)


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
