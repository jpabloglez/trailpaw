## Tests for the tree dwellers (Phase 15b): squirrels forage at the foot of their tree and run up
## it when the fox comes running, then come down; owls sit on tree tops only at night, hoot now
## and then and fly to another tree top when scared; spawning is deterministic per chunk and
## reads each chunk's trees once.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: CritterSettings = preload("res://data/critters/system.tres")
const SQUIRREL: CritterKind = preload("res://data/critters/squirrel.tres")
const OWL: CritterKind = preload("res://data/critters/owl.tres")
const SEED: int = 12345

var _saved_seed: int
var _saved_minutes: float
var _sampler: HeightSampler
var _lookups: int = 0


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_minutes = GameState.game_minutes
	GameState.world_seed = SEED
	GameState.game_minutes = 12.0 * 60.0
	_sampler = HeightSampler.new(TERRAIN, SEED)
	_lookups = 0


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.game_minutes = _saved_minutes


# Forest chunks east of the spawn (the second band).
func _forest(count: int) -> Array[Vector2i]:
	var resolver := BiomeResolver.new(TERRAIN.biomes, SEED)
	var out: Array[Vector2i] = []
	for cx in range(10, 30):
		for cz in range(-2, 3):
			var centre := (Vector2(cx, cz) + Vector2(0.5, 0.5)) * TERRAIN.chunk_size
			if resolver.dominant_at(centre.x, centre.y).id == &"forest" and out.size() < count:
				out.append(Vector2i(cx, cz))
	return out


# Six trees per chunk, their crowns 6 m above the ground.
func _trees(coord: Vector2i) -> PackedVector3Array:
	_lookups += 1
	var out := PackedVector3Array()
	for n in 6:
		var x := (coord.x + 0.15 + 0.13 * n) * TERRAIN.chunk_size
		var z := (coord.y + 0.2 + 0.11 * ((n * 3) % 6)) * TERRAIN.chunk_size
		out.append(Vector3(x, _sampler.height_at(x, z) + 6.0, z))
	return out


func _system() -> Array:
	var player: Node3D = auto_free(Node3D.new())
	player.position = Vector3(100000, 0, 100000)
	add_child(player)
	var system: TreeLife = auto_free(TreeLife.new())
	system.kinds = [SQUIRREL, OWL] as Array[CritterKind]
	system.settings = SETTINGS
	system.terrain = TERRAIN
	system.player = player
	system.tree_source = _trees
	add_child(system)
	system.set_physics_process(false)
	system.set_process(false)
	return [system, player]


func _step(system: TreeLife) -> void:
	system.tick(1.0 / SETTINGS.sim_hz)
	system.advance(1.0 / SETTINGS.sim_hz)


func _first(system: TreeLife, id: StringName) -> int:
	for i in system.count():
		if system.kind_of(i).id == id:
			return i
	return -1


func test_squirrels_live_at_the_foot_of_their_trees_and_owls_on_top() -> void:
	var system: TreeLife = _system()[0]
	var chunks := _forest(12)
	system.sync(chunks)
	assert_int(system.count_of(&"squirrel")).is_greater(2)
	assert_int(system.count_of(&"owl")).is_greater(0)
	for i in system.count():
		var at := system.position_of(i)
		var top := system.tree_of(i)
		if system.kind_of(i).id == &"squirrel":
			assert_float(Vector2(at.x - top.x, at.z - top.z).length()).is_less_equal(
				SQUIRREL.home_radius + 0.01
			)
			assert_float(at.y).is_equal_approx(_sampler.height_at(at.x, at.z), 0.01)  # on the ground
		else:
			assert_vector(at).is_equal_approx(system.perch_point(top), Vector3.ONE * 1e-3)
			assert_float(at.y).is_greater(top.y)  # on the crown's real top, not inside it
	var again: TreeLife = _system()[0]
	again.sync(chunks)
	assert_int(again.count()).is_equal(system.count())  # the same chunk brings the same ones
	for i in system.count():
		assert_vector(again.position_of(i)).is_equal(system.position_of(i))
	_lookups = 0
	system.sync(chunks)  # nothing new: no tree is read again
	assert_int(_lookups).is_equal(0)


func test_a_scared_squirrel_runs_up_its_tree_and_comes_down_later() -> void:
	var made := _system()
	var system: TreeLife = made[0]
	var player: Node3D = made[1]
	system.sync(_forest(12))
	var i := _first(system, &"squirrel")
	assert_int(i).is_greater_equal(0)
	var start := system.position_of(i)
	player.position = start + Vector3(5.0, 0.0, 0.0)
	system.tick(0.0)
	for t in int(0.5 * SETTINGS.sim_hz):  # running at it
		player.position += (start - player.position).normalized() * 7.5 / SETTINGS.sim_hz
		_step(system)
	assert_int(system.state_of(i)).is_equal(TreeLife.State.UP)
	for t in int(2.0 * SETTINGS.sim_hz):
		_step(system)
	var up := system.position_of(i)
	var top := system.tree_of(i)
	var off_axis := Vector2(up.x - top.x, up.z - top.z).length()
	assert_float(off_axis).is_equal_approx(TreeLife.TRUNK_RADIUS, 0.02)  # clinging to the trunk
	assert_float(up.y - _sampler.height_at(top.x, top.z)).is_greater(2.0)  # well up it
	player.position = start + Vector3(40.0, 0.0, 0.0)  # the fox leaves
	for t in int((SQUIRREL.calm_seconds + 3.0) * SETTINGS.sim_hz):
		_step(system)
	assert_int(system.state_of(i)).is_equal(TreeLife.State.GROUND)
	var down := system.position_of(i)  # on the ground, or at most a forage hop above it
	assert_float(down.y - _sampler.height_at(down.x, down.z)).is_between(
		-0.05, SQUIRREL.graze_hop.y + 0.05
	)


func test_owls_are_out_at_night_hoot_and_fly_to_another_tree_when_scared() -> void:
	var made := _system()
	var system: TreeLife = made[0]
	var player: Node3D = made[1]
	system.sync(_forest(12))
	var i := _first(system, &"owl")
	assert_int(i).is_greater_equal(0)
	system.tick(0.0)
	assert_bool(system.is_shown(i)).is_false()  # midday: asleep
	GameState.game_minutes = 23.0 * 60.0
	var perch := system.position_of(i)
	player.position = perch + Vector3(30.0, -6.0, 0.0)  # within earshot, not scaring it
	for t in int(100.0 * SETTINGS.sim_hz):
		_step(system)
	assert_bool(system.is_shown(i)).is_true()
	assert_int(system.hoots).is_greater(1)
	assert_int(system.state_of(i)).is_equal(TreeLife.State.PERCH)
	player.position = perch + Vector3(2.0, -6.0, 0.0)  # right under it
	_step(system)
	assert_int(system.state_of(i)).is_equal(TreeLife.State.FLY)
	player.position = perch + Vector3(80.0, -6.0, 0.0)
	for t in int((OWL.flee_hop.z + 1.0) * SETTINGS.sim_hz):
		_step(system)
	assert_int(system.state_of(i)).is_equal(TreeLife.State.PERCH)
	var landed := system.position_of(i)
	assert_float(Vector2(landed.x - perch.x, landed.z - perch.z).length()).is_between(
		OWL.flee_hop.x * 0.5, OWL.flee_hop.x * 1.5
	)
	var on_a_top := false
	for coord in _forest(12):
		for top in _trees(coord):
			on_a_top = on_a_top or landed.distance_to(system.perch_point(top)) < 0.01
	assert_bool(on_a_top).is_true()
