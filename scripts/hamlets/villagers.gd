class_name Villagers
extends Node
## The people of the hamlets: 1–3 per hamlet, built with it (as children of its root, like the
## [FarmLife]). Each has a house and a day ([method activity]): out to the well in the morning,
## work at the pen or the stable, the well again at midday, more work, a rest by the door, then
## home for the night (indoors: hidden). They walk between those spots by way of the yard.
## [br][br]
## They are wary of the fox: inside their field of view and within
## [member VillagerSettings.notice_radius] they stop and watch it; within
## [member VillagerSettings.shoo_radius] (or [member VillagerSettings.food_shoo_radius] while it
## is at their food, see [method set_food_alert]) they shoo it — a gesture, and
## [code]EventBus.fox_shooed[/code], which sends the fox off ([Shooed]).
## [br][br]
## Budget: a handful of people; decisions at 10 Hz, movement each frame; no height samples (the
## hamlets are flat: they walk on their spots' heights).

## Villager states.
enum State { INSIDE, WALK, STAY, WATCH, SHOO }

## Look, day and wariness.
@export var settings: VillagerSettings
## The hamlets they live in.
@export var director: HamletDirector
## The player (the fox they watch); defaults to the [code]player[/code] group.
@export var player: Node3D

var _node: Array[Node3D] = []
var _anim: Array[AnimationPlayer] = []
var _cell: Array[Vector2i] = []
var _door := PackedVector3Array()  # local to the hamlet's root
var _well := PackedVector3Array()
var _work := PackedVector3Array()
var _rest := PackedVector3Array()
var _offset := PackedFloat32Array()  # hours added to the day's times
var _path: Array[PackedVector3Array] = []  # points still to walk to
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _cooldown := PackedFloat32Array()
var _since: float = 0.0
var _food_alert: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x7111
	if director != null:
		director.hamlet_built.connect(populate)
		director.hamlet_freed.connect(forget)


func _process(delta: float) -> void:
	_since += delta
	if _since >= 0.1:
		think(_since)
		_since = 0.0
	walk(delta)


## Settles the villagers of [param layout] in their houses (seeded per hamlet).
func populate(layout: HamletLayout, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layout.cell) ^ 0x7111
	var houses: Array[int] = []
	for i in layout.size():
		if director.terrain.hamlets.house_ids.has(layout.ids[i]):
			houses.append(i)
	if houses.is_empty():
		return
	var work_spots := _work_spots(layout)
	for n in mini(rng.randi_range(settings.per_hamlet.x, settings.per_hamlet.y), houses.size()):
		var h := houses[(n * 2) % houses.size()]
		var house := layout.positions[h] - layout.centre
		var toward := -Vector3(house.x, 0.0, house.z).normalized()
		var door := house + toward * (layout.radii[h] * 0.85)
		var angle := rng.randf() * TAU
		var well := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(2.5, 4.0)  # (level with it)
		_add(layout, root, door, well, work_spots[n % work_spots.size()], door + toward * 2.0, rng)


## Drops the villagers of the hamlet of [param cell] (their nodes go with its root).
func forget(cell: Vector2i) -> void:
	for i in range(_node.size() - 1, -1, -1):
		if _cell[i] == cell:
			_remove(i)


## While on, villagers shoo the fox from farther away ([member VillagerSettings.food_shoo_radius]):
## it is at their food (Phase 16: eggs and vegetables).
func set_food_alert(on: bool) -> void:
	_food_alert = on


## Whether they are on alert (the fox at their food).
func food_alert() -> bool:
	return _food_alert


## What a villager does at [param hour] with its own [param offset] (hours):
## [code]&"home"[/code], [code]&"well"[/code], [code]&"work"[/code] or [code]&"rest"[/code].
func activity(hour: float, offset: float) -> StringName:
	var s := settings
	var h := fposmod(hour - offset, 24.0)
	if h < s.wake or h >= s.night:
		return &"home"
	if h < s.work:
		return &"well"
	if h < s.midday:
		return &"work"
	if h < s.afternoon:
		return &"well"
	if h < s.evening:
		return &"work"
	return &"rest"


## Decides what each villager does now: its routine, or watching and shooing the fox.
## [param elapsed] seconds since the last call.
func think(elapsed: float) -> void:
	var hour := GameState.time_of_day() / 60.0
	var focus := _player()
	for i in _node.size():
		if not is_instance_valid(_node[i]):
			continue
		_cooldown[i] -= elapsed
		_timer[i] -= elapsed
		var doing := activity(hour, _offset[i])
		if _state[i] != State.INSIDE and focus != null and _wary(i, focus.global_position):
			continue
		match _state[i]:
			State.INSIDE:
				if doing != &"home":
					_node[i].visible = true
					_go(i, _spot(i, doing))
			State.WALK:
				pass  # keeps walking (see walk())
			State.STAY, State.WATCH, State.SHOO:
				if _state[i] == State.SHOO and _timer[i] > 0.0:
					continue
				var spot := _spot(i, doing)
				if _node[i].position.distance_to(spot) > 0.5:
					_go(i, spot)
				elif doing == &"home":
					_state[i] = State.INSIDE
					_node[i].visible = false
				elif _state[i] != State.STAY:
					_stay(i, doing)


## Moves walking villagers along their path (every frame).
func walk(delta: float) -> void:
	for i in _node.size():
		if _state[i] != State.WALK or not is_instance_valid(_node[i]):
			continue
		if _path[i].is_empty():
			_arrive(i)
			continue
		var target := _path[i][0]
		var here := _node[i].position
		var step := settings.walk_speed * delta
		var to := target - here
		if to.length() <= step:
			_node[i].position = target
			_path[i].remove_at(0)
			continue
		_node[i].position = here + to.normalized() * step
		_face(i, to)


## Villagers alive.
func count() -> int:
	return _node.size()


## Where villager [param i] is (global).
func position_of(i: int) -> Vector3:
	return _node[i].global_position


## State of villager [param i] (a [enum State] value).
func state_of(i: int) -> int:
	return _state[i]


## Whether villager [param i] is outdoors.
func is_out(i: int) -> bool:
	return _node[i].visible


## The global spot villager [param i] goes to for [param doing] (see [method activity]).
func spot_of(i: int, doing: StringName) -> Vector3:
	return (_node[i].get_parent() as Node3D).global_position + _spot(i, doing)


## The direction villager [param i] faces (world X/Z, unit).
func facing_of(i: int) -> Vector3:
	var f := -_node[i].global_basis.z
	return Vector3(f.x, 0.0, f.z).normalized()


## Its own offset on the day's times (hours).
func offset_of(i: int) -> float:
	return _offset[i]


# Watching and shooing: true while the fox has its attention (the routine waits).
func _wary(i: int, fox: Vector3) -> bool:
	var here := _node[i].global_position
	var to_fox := Vector3(fox.x - here.x, 0.0, fox.z - here.z)
	var distance := to_fox.length()
	var facing := -_node[i].global_basis.z
	var in_view := (
		distance < 0.5
		or (
			rad_to_deg(Vector3(facing.x, 0.0, facing.z).angle_to(to_fox))
			<= settings.field_of_view * 0.5
		)
	)
	var watching := _state[i] == State.WATCH or _state[i] == State.SHOO
	if distance > settings.notice_radius * (1.2 if watching else 1.0) or not (in_view or watching):
		return _state[i] == State.SHOO and _timer[i] > 0.0
	var reach := settings.food_shoo_radius if _food_alert else settings.shoo_radius
	_face(i, to_fox)
	if distance <= reach and _cooldown[i] <= 0.0:
		_state[i] = State.SHOO
		_timer[i] = 1.2
		_cooldown[i] = settings.shoo_cooldown
		_play(i, settings.shoo_clip, settings.shoo_speed)
		EventBus.fox_shooed.emit(here)
	elif _state[i] != State.SHOO or _timer[i] <= 0.0:
		_state[i] = State.WATCH
		_play(i, settings.idle_clip)
	return true


func _spot(i: int, doing: StringName) -> Vector3:
	match doing:
		&"well":
			return _well[i]
		&"work":
			return _work[i]
		&"rest":
			return _rest[i]
	return _door[i]


# Walks to [param spot] by way of the yard (radial lines from the well are clear of houses).
func _go(i: int, spot: Vector3) -> void:
	var here := _node[i].position
	var path := PackedVector3Array()
	if here.length() > 8.0 and spot.length() > 8.0 and here.distance_to(spot) > 6.0:
		path.append(
			(
				Vector3(here.x, 0.0, here.z).normalized() * 5.0
				+ Vector3.UP * lerpf(here.y, spot.y, 0.5)
			)
		)
	path.append(spot)
	_path[i] = path
	_state[i] = State.WALK
	_play(i, settings.walk_clip)


func _arrive(i: int) -> void:
	var doing := activity(GameState.time_of_day() / 60.0, _offset[i])
	if doing == &"home" and _node[i].position.distance_to(_door[i]) < 0.6:
		_state[i] = State.INSIDE
		_node[i].visible = false
		return
	_stay(i, doing)


func _stay(i: int, doing: StringName) -> void:
	_state[i] = State.STAY
	if doing == &"work":
		_face(i, _work_face(i))
		_play(i, settings.work_clip)
	else:
		if doing == &"well":
			_face(i, -_node[i].position)  # towards the well (and the others there)
		_play(i, settings.idle_clip)


func _work_face(i: int) -> Vector3:
	return -_work[i] if _work[i].length() > 0.1 else Vector3.FORWARD


func _face(i: int, direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() > 0.01:
		_node[i].rotation.y = atan2(-direction.x, -direction.z)


# Where villagers work: by the pen (outside its fence) and in front of the stable.
func _work_spots(layout: HamletLayout) -> PackedVector3Array:
	var out := PackedVector3Array()
	if layout.pen != Vector3.INF:
		var pen := layout.pen - layout.centre
		out.append(pen + (-pen).normalized() * (layout.pen_half + 1.2))
	for i in layout.size():
		if layout.ids[i] == &"stable":
			var stable := layout.positions[i] - layout.centre
			out.append(stable + (-stable).normalized() * (layout.radii[i] + 1.0))
	if out.is_empty():
		out.append(Vector3(3.0, 0.0, 0.0))
	return out


func _add(
	layout: HamletLayout,
	root: Node3D,
	door: Vector3,
	well: Vector3,
	work: Vector3,
	rest: Vector3,
	rng: RandomNumberGenerator
) -> void:
	var node := Node3D.new()
	node.name = "Villager"
	var model: Node3D = settings.scene.instantiate()
	model.scale = Vector3.ONE * settings.model_scale
	model.rotation.y = PI  # the model faces +Z; here forward is −Z
	node.add_child(model)
	root.add_child(node)
	if not settings.palettes.is_empty():
		var look := StandardMaterial3D.new()
		look.albedo_texture = settings.palettes[rng.randi() % settings.palettes.size()]
		look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		look.roughness = 0.9
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = look
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false).front()
	for clip: String in [settings.idle_clip, settings.walk_clip, settings.work_clip]:
		if player != null and player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	node.position = door
	node.visible = false
	_node.append(node)
	_anim.append(player)
	_cell.append(layout.cell)
	_door.append(door)
	_well.append(well)
	_work.append(work)
	_rest.append(rest)
	_offset.append(rng.randf_range(-settings.jitter, settings.jitter))
	_path.append(PackedVector3Array())
	_state.append(State.INSIDE)
	_timer.append(0.0)
	_cooldown.append(0.0)


func _play(i: int, clip: String, speed: float = 1.0) -> void:
	var player := _anim[i]
	if player != null and player.has_animation(clip):
		if player.current_animation != clip:
			player.play(clip)
		player.speed_scale = speed


func _remove(i: int) -> void:
	_node.remove_at(i)
	_anim.remove_at(i)
	_cell.remove_at(i)
	_door.remove_at(i)
	_well.remove_at(i)
	_work.remove_at(i)
	_rest.remove_at(i)
	_offset.remove_at(i)
	_path.remove_at(i)
	_state.remove_at(i)
	_timer.remove_at(i)
	_cooldown.remove_at(i)


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
