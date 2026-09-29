## Tests for per-chunk resource deltas ([ChunkDeltaStore]): persistence across chunk unload and
## reload, LOD changes, pruning and serialisation.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const SEED: int = 12345
const FOREST := Vector2i(17, 2)
const MEADOW := Vector2i(3, 3)
const FOX_DIET: Array[StringName] = [&"berries", &"fruit", &"mushroom"]

var _settings: TerrainSettings
var _scatterer: VegetationScatterer
var _library: VegetationLibrary
var _saved_minutes: float


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_scatterer = VegetationScatterer.new(_settings.biomes)
	_library = VegetationLibrary.new(_settings.biomes)


func before_test() -> void:
	_saved_minutes = GameState.game_minutes
	GameState.game_minutes = 1000.0


func after_test() -> void:
	GameState.game_minutes = _saved_minutes


func _gen(coord: Vector2i, lod: int = 0) -> ChunkData:
	return ChunkGenerator.generate_with(
		coord, lod, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED
	)


func _chunk(store: ChunkDeltaStore) -> TerrainChunk:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	chunk.delta_store = store
	add_child(chunk)
	return chunk


func _apply(chunk: TerrainChunk, coord: Vector2i, lod: int = 0) -> void:
	chunk.apply(_gen(coord, lod), load(MATERIAL_PATH), _library, FOX_DIET)


## Index of the first berries target of [param chunk] and its instance index.
func _first_berries(chunk: TerrainChunk) -> Vector2i:
	for i in chunk.food_count():
		var target := chunk.interaction_target(i)
		if target.definition.id == &"berries":
			return Vector2i(i, target.key & 0xFFFF)
	return Vector2i(-1, -1)


# --- store --------------------------------------------------------------------------------


func test_store_depletes_until_the_regrow_time() -> void:
	var store := ChunkDeltaStore.new()
	store.deplete(FOREST, &"berries", 7, 1200.0)
	assert_bool(store.is_depleted(FOREST, &"berries", 7, 1100.0)).is_true()
	assert_bool(store.is_depleted(FOREST, &"berries", 8, 1100.0)).is_false()
	assert_bool(store.is_depleted(MEADOW, &"berries", 7, 1100.0)).is_false()
	assert_bool(store.is_depleted(FOREST, &"berries", 7, 1200.0)).is_false()


func test_regrown_entries_are_pruned() -> void:
	var store := ChunkDeltaStore.new()
	store.deplete(FOREST, &"berries", 1, 1100.0)
	store.deplete(FOREST, &"apple", 2, 1300.0)
	store.deplete(MEADOW, &"berries", 3, 1150.0)
	store.prune(1200.0)
	assert_int(store.size()).is_equal(1)
	assert_bool(store.entries_for(MEADOW).is_empty()).is_true()
	var regrown := store.take_regrown(FOREST, 1300.0)
	assert_array(regrown).contains_exactly([[&"apple", 2]])
	assert_int(store.size()).is_equal(0)


func test_to_dict_round_trips() -> void:
	var store := ChunkDeltaStore.new()
	store.deplete(FOREST, &"berries", 7, 1200.5)
	store.deplete(Vector2i(-40, 12), &"mushroom_tan", 0, 99999.0)
	var data := store.to_dict()
	assert_int(data["version"]).is_equal(ChunkDeltaStore.VERSION)
	# Survives a JSON trip (what a save file would do).
	var restored := ChunkDeltaStore.new()
	restored.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_int(restored.size()).is_equal(2)
	assert_bool(restored.is_depleted(FOREST, &"berries", 7, 1200.0)).is_true()
	assert_bool(restored.is_depleted(FOREST, &"berries", 7, 1200.5)).is_false()
	assert_bool(restored.is_depleted(Vector2i(-40, 12), &"mushroom_tan", 0, 5000.0)).is_true()


# --- chunks -------------------------------------------------------------------------------


func test_deltas_persist_across_chunk_unload_and_reload() -> void:
	var store := ChunkDeltaStore.new()
	var first := _chunk(store)
	_apply(first, FOREST)
	var berries := _first_berries(first)
	first.interaction_target(berries.x).consume()
	# The chunk unloads: its pooled node is reused for another chunk…
	_apply(first, MEADOW)
	# …and later the forest chunk loads again in a different node.
	var second := _chunk(store)
	_apply(second, FOREST)
	assert_bool(second.is_depleted(&"berries", berries.y)).is_true()
	assert_bool(second.is_hidden(&"berries", berries.y)).is_true()  # still drawn eaten
	assert_bool(second.interaction_target(berries.x).is_available()).is_false()
	# The meadow chunk the first node now shows is unaffected.
	assert_bool(first.is_depleted(&"berries", berries.y)).is_false()


func test_regrowth_while_unloaded_is_applied_on_reload() -> void:
	var store := ChunkDeltaStore.new()
	var chunk := _chunk(store)
	_apply(chunk, FOREST)
	var berries := _first_berries(chunk)
	var target := chunk.interaction_target(berries.x)
	target.consume()
	_apply(chunk, MEADOW)  # unloaded
	GameState.game_minutes += target.definition.regrowth_minutes
	_apply(chunk, FOREST)  # back after the regrowth time
	assert_bool(chunk.interaction_target(berries.x).is_available()).is_true()
	assert_bool(chunk.is_hidden(&"berries", berries.y)).is_false()
	assert_int(store.size()).is_equal(0)  # pruned


func test_lod_changes_keep_the_state() -> void:
	var store := ChunkDeltaStore.new()
	var chunk := _chunk(store)
	_apply(chunk, FOREST)
	var berries := _first_berries(chunk)
	chunk.interaction_target(berries.x).consume()
	_apply(chunk, FOREST, 1)  # far away: coarse, no food targets
	assert_int(chunk.food_count()).is_equal(0)
	_apply(chunk, FOREST, 0)  # close again
	assert_bool(chunk.interaction_target(berries.x).is_available()).is_false()
	assert_bool(chunk.is_hidden(&"berries", berries.y)).is_true()


func test_a_regrown_instance_is_never_edible_while_still_hidden() -> void:
	var store := ChunkDeltaStore.new()
	var chunk := _chunk(store)
	_apply(chunk, FOREST)
	var berries := _first_berries(chunk)
	var target := chunk.interaction_target(berries.x)
	target.consume()
	GameState.game_minutes += target.definition.regrowth_minutes + 1.0
	assert_bool(target.is_available()).is_false()  # until regrow() shows it
	assert_bool(chunk.is_hidden(&"berries", berries.y)).is_true()
	chunk.regrow()
	assert_bool(target.is_available()).is_true()
	assert_bool(chunk.is_hidden(&"berries", berries.y)).is_false()


func test_the_streamer_shares_one_store_with_every_chunk() -> void:
	var streamer: WorldStreamer = auto_free(WorldStreamer.new())
	streamer.terrain = _settings
	streamer.streaming = load("res://data/world/streaming_settings.tres")
	streamer.chunk_scene = load(CHUNK_SCENE)
	streamer.material = load(MATERIAL_PATH)
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	streamer.target = target
	add_child(streamer)
	for i in 60:
		await get_tree().process_frame
		if streamer.is_idle() and i > 5:
			break
	var coords := streamer.loaded_coords()
	assert_int(coords.size()).is_greater(1)
	for coord in coords:
		assert_object(streamer.get_chunk(coord).delta_store).is_same(streamer.deltas())
