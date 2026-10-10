## Tests for the hamlets' food (Phase 16): every hamlet has a vegetable patch and a hens' nest;
## their cabbages and eggs are food the fox can eat; eaten ones stay gone (also once the hamlet is
## freed and built again) until they regrow a day later; and while the fox is at the food the
## villagers are on alert.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const EGGS: InteractionDefinition = preload("res://data/interactions/eggs.tres")
const VEGETABLES: InteractionDefinition = preload("res://data/interactions/vegetables.tres")
const VILLAGERS: VillagerSettings = preload("res://data/hamlets/villagers.tres")
const FOX: AnimalSpecies = preload("res://data/species/fox.tres")

var _saved_seed: int
var _saved_minutes: float


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_minutes = GameState.game_minutes
	GameState.world_seed = 12345
	GameState.game_minutes = 10.0 * 60.0


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.game_minutes = _saved_minutes


func _hamlet() -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var director: HamletDirector = auto_free(HamletDirector.new())
	director.terrain = TERRAIN
	director.player = player
	add_child(director)
	director.set_process(false)
	var hamlet: HamletLayout = director.hamlets_near(Vector3.ZERO, 2000.0)[0]
	player.global_position = GameState.local_position(hamlet.centre + Vector3(0, 0, 100))
	var villagers: Villagers = auto_free(Villagers.new())
	villagers.settings = VILLAGERS
	villagers.director = director
	villagers.player = player
	add_child(villagers)
	villagers.set_process(false)
	var food: HamletFood = auto_free(HamletFood.new())
	food.director = director
	food.villagers = villagers
	food.player = player
	food.eggs = EGGS
	food.vegetables = VEGETABLES
	food.deltas = ChunkDeltaStore.new()
	add_child(food)
	food.set_process(false)
	director.refresh()
	director.build_all_now()
	return [food, player, hamlet, director, villagers]


func test_every_hamlet_has_a_patch_and_a_nest_full_of_food() -> void:
	for cx in range(-4, 4):
		for cz in range(-4, 4):
			var sampler := HeightSampler.new(TERRAIN, 12345)
			var layout := HamletPlan.layout(
				Vector2i(cx, cz), TERRAIN.hamlets, sampler, 12345, TERRAIN.sea_level
			)
			if layout != null:
				assert_bool(layout.ids.has(&"patch")).is_true()
				assert_bool(layout.ids.has(&"nest")).is_true()
	var made := _hamlet()
	var food: HamletFood = made[0]
	var pantry := food.pantry((made[2] as HamletLayout).cell)
	assert_int(pantry.count()).is_equal(9)
	var kinds := {}
	for key in pantry.count():
		var target := pantry.interaction_target(key)
		assert_object(target).is_not_null()
		assert_bool(target.is_available()).is_true()
		kinds[target.definition.id] = kinds.get(target.definition.id, 0) + 1
	assert_dict(kinds).is_equal({&"vegetables": 6, &"eggs": 3})
	assert_bool(FOX.diet.has(&"eggs") and FOX.diet.has(&"vegetables")).is_true()  # the fox eats them
	assert_int(pantry.collision_layer).is_equal(Interactable.LAYER)


func test_eaten_food_stays_gone_until_it_regrows_even_after_a_rebuild() -> void:
	var made := _hamlet()
	var food: HamletFood = made[0]
	var player: Node3D = made[1]
	var hamlet: HamletLayout = made[2]
	var director: HamletDirector = made[3]
	var pantry := food.pantry(hamlet.cell)
	var egg := -1
	for key in pantry.count():
		if pantry.definition_of(key) == EGGS:
			egg = key
	pantry.interaction_target(egg).consume()
	assert_bool(pantry.is_target_available(egg)).is_false()
	player.global_position += Vector3(3000, 0, 0)  # away: the hamlet is freed…
	director.refresh()
	assert_object(food.pantry(hamlet.cell)).is_null()
	player.global_position -= Vector3(3000, 0, 0)  # …and built again
	director.refresh()
	director.build_all_now()
	var again := food.pantry(hamlet.cell)
	assert_bool(again.is_target_available(egg)).is_false()  # still eaten
	assert_bool(again.is_target_available((egg + 1) % again.count())).is_true()
	GameState.game_minutes += EGGS.regrowth_minutes + 1.0  # a day later
	assert_bool(again.is_target_available(egg)).is_true()


func test_villagers_are_on_alert_while_the_fox_is_at_their_food() -> void:
	var made := _hamlet()
	var food: HamletFood = made[0]
	var player: Node3D = made[1]
	var pantry := food.pantry((made[2] as HamletLayout).cell)
	var seen := [0]
	var count_seen := func() -> void: seen[0] += 1
	EventBus.hamlet_food_seen.connect(count_seen)
	assert_bool(food.check()).is_false()  # 100 m away
	var villagers: Villagers = made[4]
	assert_bool(villagers.food_alert()).is_false()
	player.global_position = pantry.position_of(0) + Vector3(1.0, 0.0, 0.0)
	assert_bool(food.check()).is_true()
	assert_bool(villagers.food_alert()).is_true()  # they watch their food
	assert_int(seen[0]).is_equal(1)
	food.check()
	assert_int(seen[0]).is_equal(1)  # announced once
	for key in pantry.count():  # all eaten: nothing left to guard
		pantry.consume_target(key)
	player.global_position = pantry.position_of(0) + Vector3(0.3, 0.0, 0.0)
	assert_bool(food.check()).is_false()  # eaten food is no lure
	assert_bool(villagers.food_alert()).is_false()
	EventBus.hamlet_food_seen.disconnect(count_seen)
