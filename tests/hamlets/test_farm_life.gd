## Tests for the hamlets' animals (Phase 16): sheep, pigs and cows stay in the stable's pen, keep
## apart and move (cows walk, the others hop); chickens peck about their spot, scatter when the fox
## comes running and are indoors at night.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const KINDS: Array[FarmAnimalKind] = [
	preload("res://data/hamlets/farm/sheep.tres"),
	preload("res://data/hamlets/farm/pig.tres"),
	preload("res://data/hamlets/farm/cow.tres"),
]
const CHICKEN: CritterKind = preload("res://data/hamlets/farm/chicken.tres")
const SEED: int = 12345

var _saved_seed: int
var _saved_minutes: float


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_minutes = GameState.game_minutes
	GameState.world_seed = SEED
	GameState.game_minutes = 12.0 * 60.0


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.game_minutes = _saved_minutes


func _farm() -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var director: HamletDirector = auto_free(HamletDirector.new())
	director.terrain = TERRAIN
	director.player = player
	add_child(director)
	director.set_process(false)
	var hamlet: HamletLayout = director.hamlets_near(Vector3.ZERO, 2000.0)[0]
	player.global_position = GameState.local_position(hamlet.centre + Vector3(0, 0, 60))
	var farm: FarmLife = auto_free(FarmLife.new())
	farm.director = director
	farm.kinds = KINDS
	farm.chicken = CHICKEN
	farm.player = player
	add_child(farm)
	farm.set_process(false)
	director.refresh()
	director.build_all_now()
	return [farm, player, hamlet, director]


func _run(farm: FarmLife, seconds: float) -> void:
	for t in int(seconds * 30.0):
		farm.step(1.0 / 30.0)


func _penned(farm: FarmLife) -> Array[int]:
	var out: Array[int] = []
	for i in farm.count():
		if farm.kind_of(i) is FarmAnimalKind:
			out.append(i)
	return out


func test_the_pen_holds_animals_that_stay_in_it_and_keep_apart() -> void:
	var made := _farm()
	var farm: FarmLife = made[0]
	var hamlet: HamletLayout = made[2]
	assert_bool(hamlet.pen != Vector3.INF).is_true()
	var penned := _penned(farm)
	assert_int(penned.size()).is_between(3, 5)
	var start: Array[Vector3] = []
	for i in penned:
		start.append(farm.position_of(i))
	var moved := 0.0
	for t in 60:
		_run(farm, 1.0)
		for n in penned.size():
			var i := penned[n]
			var home := farm.home_of(i)
			var at := farm.position_of(i)
			var off := Vector2(at.x - home.x, at.z - home.z).length()
			assert_float(off).is_less_equal(home.w + 0.05)  # never out of the pen
			moved = maxf(moved, at.distance_to(start[n]))
	assert_float(moved).is_greater(0.5)  # they do move about
	for a in penned:
		for b in penned:
			if (
				a < b
				and farm.state_of(a) == FarmLife.State.IDLE
				and farm.state_of(b) == FarmLife.State.IDLE
			):
				var gap := farm.position_of(a).distance_to(farm.position_of(b))
				assert_float(gap).is_greater(FarmLife.ROOM * 0.8)  # not inside one another


func test_the_models_have_their_clips_and_sensible_sizes() -> void:
	var heights := {}
	for kind in KINDS:
		var model: Node3D = auto_free(kind.scene.instantiate())
		model.scale = Vector3.ONE * kind.model_scale
		add_child(model)
		await get_tree().process_frame
		var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
		(
			assert_bool(player.has_animation(kind.idle_clip))
			. override_failure_message(String(kind.id))
			. is_true()
		)
		(
			assert_bool(player.has_animation(kind.move_clip))
			. override_failure_message(String(kind.id))
			. is_true()
		)
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var head := (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
		)
		heights[kind.id] = head.y
	assert_float(heights[&"cow"]).is_greater(heights[&"sheep"])
	assert_float(heights[&"sheep"]).is_greater(heights[&"pig"])
	assert_float(heights[&"cow"]).is_between(1.2, 1.8)
	assert_float(heights[&"pig"]).is_between(0.4, 0.8)
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for kind in KINDS:
		assert_str(credits).contains("assets/animals/%s/%s.glb" % [kind.id, kind.id])


func test_chickens_scatter_from_a_running_fox_and_go_indoors_at_night() -> void:
	var made := _farm()
	var farm: FarmLife = made[0]
	var player: Node3D = made[1]
	var hen := -1
	for i in farm.count():
		if farm.kind_of(i) == CHICKEN:
			hen = i
	assert_int(hen).is_greater_equal(0)
	_run(farm, 1.0)
	var at := farm.position_of(hen)
	player.global_position = at + Vector3(4.0, 0.0, 0.0)
	farm.step(1.0 / 30.0)
	for t in 15:  # running at it
		player.global_position += (at - player.global_position).normalized() * 0.25
		farm.step(1.0 / 30.0)
	assert_int(farm.state_of(hen)).is_equal(FarmLife.State.SCATTER)
	player.global_position = at + Vector3(80.0, 0.0, 0.0)  # the fox goes
	_run(farm, 25.0)
	var home := farm.home_of(hen)
	var back := farm.position_of(hen)
	assert_float(Vector2(back.x - home.x, back.z - home.z).length()).is_less_equal(
		home.w + CHICKEN.flee_hop.x * 3.0
	)
	assert_bool(farm.is_shown(hen)).is_true()
	GameState.game_minutes = 23.0 * 60.0
	farm.step(1.0 / 30.0)
	assert_bool(farm.is_shown(hen)).is_false()  # in the coop for the night
