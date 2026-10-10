## Tests for the villagers (Phase 16): their day (indoors at night, the well, work), the paths they
## keep to, and their wariness — they watch a fox in front of them, shoo it when it comes close
## (closer at their food), not from behind or from afar — and the [Shooed] retreat it causes.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SETTINGS: VillagerSettings = preload("res://data/hamlets/villagers.tres")
const FOX_SPECIES: AnimalSpecies = preload("res://data/species/fox.tres")

var _saved_seed: int
var _saved_minutes: float
var _shoos: Array[Vector3] = []


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_minutes = GameState.game_minutes
	GameState.world_seed = 12345
	GameState.game_minutes = 12.5 * 60.0
	_shoos.clear()
	EventBus.fox_shooed.connect(_on_shooed)


func after_test() -> void:
	EventBus.fox_shooed.disconnect(_on_shooed)
	GameState.world_seed = _saved_seed
	GameState.game_minutes = _saved_minutes


func _on_shooed(from: Vector3) -> void:
	_shoos.append(from)


func _village(alone: bool = false) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var director: HamletDirector = auto_free(HamletDirector.new())
	director.terrain = TERRAIN
	director.player = player
	add_child(director)
	director.set_process(false)
	var hamlet: HamletLayout = director.hamlets_near(Vector3.ZERO, 2000.0)[0]
	player.global_position = GameState.local_position(hamlet.centre + Vector3(0, 0, 200))  # far
	var villagers: Villagers = auto_free(Villagers.new())
	var settings: VillagerSettings = SETTINGS.duplicate()
	if alone:  # one villager, so "behind it" is behind everyone
		settings.per_hamlet = Vector2i(1, 1)
	villagers.settings = settings
	villagers.director = director
	villagers.player = player
	add_child(villagers)
	villagers.set_process(false)
	director.refresh()
	director.build_all_now()
	return [villagers, player, hamlet, director]


func _live(villagers: Villagers, seconds: float) -> void:
	for t in int(seconds * 10.0):
		villagers.think(0.1)
		for f in 3:
			villagers.walk(1.0 / 30.0)


func test_their_day_follows_the_hour() -> void:
	var villagers: Villagers = _village()[0]
	var expected := {
		3.0: &"home",
		6.5: &"well",
		9.0: &"work",
		13.0: &"well",
		15.0: &"work",
		19.0: &"rest",
		22.0: &"home"
	}
	for hour: float in expected:
		assert_str(String(villagers.activity(hour, 0.0))).is_equal(String(expected[hour]))
	assert_str(String(villagers.activity(6.2, 0.4))).is_equal("home")  # a late riser


func test_indoors_at_night_out_by_day_at_their_spots_and_never_astray() -> void:
	var made := _village()
	var villagers: Villagers = made[0]
	var hamlet: HamletLayout = made[2]
	var root: Node3D = (made[3] as HamletDirector).hamlet_root(hamlet.cell)
	assert_int(villagers.count()).is_between(SETTINGS.per_hamlet.x, SETTINGS.per_hamlet.y)
	GameState.game_minutes = 1.0 * 60.0
	_live(villagers, 2.0)
	for i in villagers.count():
		assert_bool(villagers.is_out(i)).is_false()  # asleep at home
	GameState.game_minutes = 12.7 * 60.0  # midday: at the well
	var reach := TERRAIN.hamlets.ring.y + 10.0
	for t in 60:
		_live(villagers, 1.0)
		for i in villagers.count():
			var off := villagers.position_of(i) - root.global_position
			assert_float(Vector2(off.x, off.z).length()).is_less(reach)  # within the hamlet
	for i in villagers.count():
		assert_bool(villagers.is_out(i)).is_true()
		var spot := villagers.spot_of(i, villagers.activity(12.7, villagers.offset_of(i)))
		assert_float(villagers.position_of(i).distance_to(spot)).is_less(0.6)
		assert_int(villagers.state_of(i)).is_equal(Villagers.State.STAY)
	GameState.game_minutes = 22.0 * 60.0  # evening: home they go
	_live(villagers, 60.0)
	for i in villagers.count():
		assert_bool(villagers.is_out(i)).is_false()


# A villager standing at the well, and the direction it faces.
func _standing(villagers: Villagers) -> Array:
	GameState.game_minutes = 12.7 * 60.0
	_live(villagers, 60.0)
	for i in villagers.count():
		if villagers.state_of(i) == Villagers.State.STAY:
			return [i, villagers.position_of(i)]
	return [-1, Vector3.ZERO]


func test_a_fox_in_front_is_watched_then_shooed_once_but_not_from_behind_or_afar() -> void:
	var made := _village(true)
	var villagers: Villagers = made[0]
	var player: Node3D = made[1]
	var picked := _standing(villagers)
	var i: int = picked[0]
	assert_int(i).is_greater_equal(0)
	var at: Vector3 = picked[1]
	var ahead := villagers.facing_of(i)
	player.global_position = at + ahead.rotated(Vector3.UP, PI) * 4.0  # 4 m behind its back
	_live(villagers, 2.0)
	assert_array(_shoos).is_empty()
	player.global_position = at + ahead * 10.0  # in front, but 10 m away: it watches
	villagers.think(0.1)
	assert_int(villagers.state_of(i)).is_equal(Villagers.State.WATCH)
	assert_array(_shoos).is_empty()
	player.global_position = at + ahead * 4.0  # in front and close: shoo!
	villagers.think(0.1)
	assert_int(_shoos.size()).is_equal(1)
	assert_int(villagers.state_of(i)).is_equal(Villagers.State.SHOO)
	_live(villagers, SETTINGS.shoo_cooldown * 0.5)
	assert_int(_shoos.size()).is_equal(1)  # not again straight away
	player.global_position = at + ahead * 40.0  # gone: back to its routine
	_live(villagers, 3.0)
	assert_int(villagers.state_of(i)).is_not_equal(Villagers.State.WATCH)


func test_at_their_food_they_shoo_from_farther() -> void:
	var made := _village(true)
	var villagers: Villagers = made[0]
	var player: Node3D = made[1]
	var picked := _standing(villagers)
	var i: int = picked[0]
	var ahead := villagers.facing_of(i)
	var gap := (SETTINGS.shoo_radius + SETTINGS.food_shoo_radius) * 0.5
	player.global_position = (picked[1] as Vector3) + ahead * gap
	villagers.think(0.1)
	assert_array(_shoos).is_empty()
	villagers.set_food_alert(true)
	villagers.think(0.1)
	assert_int(_shoos.size()).is_equal(1)


func test_a_shooed_fox_backs_off_for_a_moment_then_is_free() -> void:
	var body: CharacterBody3D = auto_free(CharacterBody3D.new())
	add_child(body)
	body.global_position = Vector3(10, 0, 0)
	var movement: MovementComponent = auto_free(MovementComponent.new())
	movement.species = FOX_SPECIES
	body.add_child(movement)
	var shooed: Shooed = auto_free(Shooed.new())
	shooed.movement = movement
	shooed.body = body
	add_child(shooed)
	EventBus.fox_shooed.emit(Vector3(4, 0, 0))  # from the west
	assert_bool(shooed.is_active()).is_true()
	assert_vector(Vector3(shooed.away().x, 0, shooed.away().y)).is_equal_approx(
		Vector3.RIGHT, Vector3.ONE * 1e-4
	)
	shooed._physics_process(0.1)
	assert_bool(movement.camera_relative).is_false()
	assert_vector(Vector3(movement.move_input.x, 0, movement.move_input.y)).is_equal_approx(
		Vector3.RIGHT, Vector3.ONE * 1e-4
	)
	for t in int(shooed.seconds / 0.1) + 1:
		shooed._physics_process(0.1)
	assert_bool(shooed.is_active()).is_false()
	assert_bool(movement.camera_relative).is_true()  # the player steers again
