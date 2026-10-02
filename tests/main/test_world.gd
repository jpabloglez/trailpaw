## Integration tests for the playable world scene: new games, restoring a saved game exactly
## (also after a floating-origin rebase) and when the game saves itself.
extends GdUnitTestSuite

const WORLD_SCENE: String = "res://scenes/main/world.tscn"
const TEST_DIR: String = "user://test_world_saves"
const MAX_FRAMES: int = 1500
const EXPLORATION: ExplorationSettings = preload("res://data/world/exploration.tres")

var _saved_dir: String
var _saved_minutes: float


func before_test() -> void:
	_saved_dir = SaveSystem.save_dir
	_saved_minutes = GameState.game_minutes
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.erase()


func after_test() -> void:
	SaveSystem.erase()
	SaveSystem.save_dir = _saved_dir
	GameState.game_minutes = _saved_minutes
	FloatingOrigin.reset()


func _world(save: SaveData = null) -> WorldController:
	var world: WorldController = auto_free(load(WORLD_SCENE).instantiate())
	world.pending_save = save
	add_child(world)
	world.animal.get_node("%PlayerInput").set_physics_process(false)
	return world


func _until(condition: Callable) -> bool:
	for i in MAX_FRAMES:
		await get_tree().process_frame
		if condition.call():
			return true
	return false


func _landed(world: WorldController) -> bool:
	return await _until(func() -> bool: return not world.spawner.is_parked())


func test_a_new_game_starts_at_the_spawn_and_lands() -> void:
	var world := _world()
	assert_int(GameState.world_seed).is_equal(world.world_seed)
	assert_bool(world.spawner.is_parked()).is_true()
	assert_bool(await _landed(world)).is_true()
	var absolute: Vector3 = GameState.absolute_position(world.animal.global_position)
	assert_float(absolute.x).is_equal_approx(WorldController.NEW_GAME_POSITION.x, 0.5)
	assert_float(absolute.z).is_equal_approx(WorldController.NEW_GAME_POSITION.z, 0.5)


func test_a_saved_game_continues_exactly_where_it_was() -> void:
	var save := SaveData.new()
	save.world_seed = 777
	save.player_position = Vector3(5310.5, 20.0, -2470.25)  # 5 km out: a different origin chunk
	save.player_yaw = 2.0
	save.needs = {&"hunger": 42.0, &"thirst": 63.5, &"temperature": 77.0, &"energy": 18.0}
	save.game_minutes = 1440.0 * 2 + 1290.0  # 21:30 on the third day
	var deltas := ChunkDeltaStore.new()
	deltas.deplete(Vector2i(82, -39), &"berries", 2, save.game_minutes + 100.0)
	save.chunk_deltas = deltas.to_dict()
	var seen := ExploredMap.new(EXPLORATION)
	seen.reveal(Vector3(100, 0, 100), 96.0)  # somewhere visited long ago
	save.explored = seen.to_dict()
	var world := _world(save)
	assert_int(GameState.world_seed).is_equal(777)
	assert_float(GameState.game_minutes).is_equal(save.game_minutes)
	assert_bool(GameState.origin_chunk != Vector2i.ZERO).is_true()
	assert_float(world.animal.position.length()).is_less(200.0)  # local stays near the origin
	assert_bool(await _landed(world)).is_true()
	var back := world.collect_save()
	assert_float(back.player_position.x).is_equal_approx(save.player_position.x, 0.5)
	assert_float(back.player_position.z).is_equal_approx(save.player_position.z, 0.5)
	assert_float(back.player_yaw).is_equal_approx(2.0, 1e-4)
	for id: StringName in save.needs:
		assert_float(back.needs[id]).is_equal_approx(save.needs[id], 0.5)  # a few ticks of decay
	var restored := ChunkDeltaStore.new()
	restored.from_dict(back.chunk_deltas)
	assert_bool(restored.is_depleted(Vector2i(82, -39), &"berries", 2, save.game_minutes)).is_true()
	# The map remembers the old place and adds where the animal stands now.
	world.exploration.reveal_now()
	var map := ExploredMap.new(EXPLORATION)
	map.from_dict(world.collect_save().explored)
	assert_bool(map.is_explored(100, 100)).is_true()
	assert_bool(map.is_explored(save.player_position.x, save.player_position.z)).is_true()


func test_positions_are_saved_absolute_across_a_rebase() -> void:
	var world := _world()
	assert_bool(await _landed(world)).is_true()
	world.animal.global_position.x += 2500.0
	var before := world.collect_save().player_position
	FloatingOrigin.rebase_now()
	assert_bool(GameState.origin_chunk != Vector2i.ZERO).is_true()
	assert_vector(world.collect_save().player_position).is_equal_approx(before, Vector3.ONE * 1e-2)


func test_save_now_writes_a_game_that_reads_back() -> void:
	var world := _world()
	assert_bool(world.save_now()).is_false()  # still waiting for the ground
	assert_bool(await _landed(world)).is_true()
	assert_bool(world.save_now()).is_true()
	var read := SaveSystem.read()
	assert_object(read).is_not_null()
	assert_int(read.world_seed).is_equal(world.world_seed)
	assert_str(read.species).is_equal("res://data/species/fox.tres")


func test_autosaves_on_a_biome_change_but_not_too_often_and_every_interval() -> void:
	var world := _world()
	assert_bool(await _landed(world)).is_true()
	world.set_process(false)
	world._process(world.autosave.biome_min_gap_seconds + 1.0)
	EventBus.biome_entered.emit(&"forest", "Forest")
	assert_bool(SaveSystem.exists()).is_true()
	SaveSystem.erase()
	EventBus.biome_entered.emit(&"meadow", "Meadow")  # right after a save: skipped
	assert_bool(SaveSystem.exists()).is_false()
	world._process(world.autosave.interval_seconds + 1.0)
	assert_bool(SaveSystem.exists()).is_true()


func test_the_attract_world_never_saves() -> void:
	var world := _world()
	world.saving_enabled = false
	assert_bool(await _landed(world)).is_true()
	assert_bool(world.save_now()).is_false()
	assert_bool(SaveSystem.exists()).is_false()


func test_the_attract_world_explores_nothing() -> void:
	var world: WorldController = auto_free(load(WORLD_SCENE).instantiate())
	world.attract_mode = true
	add_child(world)
	await get_tree().process_frame
	assert_int(world.exploration.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
