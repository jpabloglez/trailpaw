## Tests for fauna spawning ([FaunaPlan], [FaunaDirector]): deterministic rolls, biome tables,
## the population cap, despawning with the chunk and by distance, spawn clearance and AI LOD.
extends GdUnitTestSuite

const SETTINGS: FaunaSettings = preload("res://data/fauna/director.tres")
const TERRAIN: String = "res://data/world/terrain_settings.tres"
const AGENT_SCENE: String = "res://scenes/fauna/fauna_agent.tscn"
const SEED: int = 12345

var _saved_seed: int
var _saved_water: float


func before_test() -> void:
	_saved_seed = GameState.world_seed
	_saved_water = GameState.water_level
	GameState.world_seed = SEED
	GameState.water_level = -INF


func after_test() -> void:
	GameState.world_seed = _saved_seed
	GameState.water_level = _saved_water


## A biome where every chunk hosts a herd of [param species].
func _busy_biome(species: String, chance: float = 1.0) -> BiomeDefinition:
	var biome := (load("res://data/biomes/meadow.tres") as BiomeDefinition).duplicate()
	var entry := FaunaEntry.new()
	entry.species = load("res://data/fauna/%s.tres" % species)
	var entries: Array[FaunaEntry] = [entry]
	biome.fauna = entries
	biome.fauna_chance = chance
	return biome


## Terrain settings whose single biome is [param biome] (every chunk resolves to it).
func _terrain(biome: BiomeDefinition) -> TerrainSettings:
	var terrain := (load(TERRAIN) as TerrainSettings).duplicate()
	var table := BiomeTable.new()
	var biomes: Array[BiomeDefinition] = [biome]
	table.biomes = biomes
	table.cycle = true
	table.blend_width = 50.0
	terrain.biomes = table
	return terrain


func _floor() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 2000)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)


func _director(biome: BiomeDefinition, at: Vector3 = Vector3(500, 0, 500)) -> FaunaDirector:
	var player: Node3D = auto_free(Node3D.new())
	player.position = at
	add_child(player)
	var director: FaunaDirector = auto_free(FaunaDirector.new())
	director.settings = SETTINGS
	director.terrain = _terrain(biome)
	director.agent_scene = load(AGENT_SCENE)
	director.player = player
	add_child(director)
	return director


func _coords_around(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			out.append(centre + Vector2i(x, z))
	return out


func _drain(director: FaunaDirector) -> void:
	while director.pending() > 0:
		await get_tree().process_frame
	await get_tree().process_frame


# --- plan ---------------------------------------------------------------------------------


func test_rolls_are_deterministic_per_chunk_and_seed() -> void:
	var biome := _busy_biome("deer")
	var a := FaunaPlan.roll(Vector2i(3, -2), 64.0, biome, SEED, 12.0)
	var b := FaunaPlan.roll(Vector2i(3, -2), 64.0, biome, SEED, 12.0)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_vector(a[i][1]).is_equal(b[i][1])
		assert_int(a[i][2]).is_equal(b[i][2])
	var other := FaunaPlan.roll(Vector2i(3, -2), 64.0, biome, SEED + 1, 12.0)
	assert_bool(other.size() != a.size() or other[0][1] != a[0][1]).is_true()


func test_herds_use_the_species_size_and_stay_near_the_chunk_centre() -> void:
	var biome := _busy_biome("deer")
	var deer: FaunaSpecies = biome.fauna[0].species
	for i in 40:
		var coord := Vector2i(i, -i)
		var herd := FaunaPlan.roll(coord, 64.0, biome, SEED, 12.0)
		assert_int(herd.size()).is_between(deer.herd_size.x, deer.herd_size.y)
		var centre := (Vector2(coord) + Vector2(0.5, 0.5)) * 64.0
		for spawn: Array in herd:
			assert_object(spawn[0]).is_same(deer)
			assert_float((spawn[1] as Vector2).distance_to(centre)).is_less_equal(12.0 + 1e-3)


func test_the_chunk_chance_is_respected() -> void:
	var biome := _busy_biome("stag", 0.15)
	var hosting := 0
	for i in 1000:
		hosting += int(
			not FaunaPlan.roll(Vector2i(i % 40, i / 40), 64.0, biome, SEED, 12.0).is_empty()
		)
	assert_int(hosting).is_between(110, 190)


func test_every_biome_hosts_valid_fauna() -> void:
	var table := (load(TERRAIN) as TerrainSettings).biomes
	for biome in table.biomes:
		assert_float(biome.fauna_chance).is_between(0.05, 0.3)
		assert_bool(biome.fauna.is_empty()).is_false()
		for entry in biome.fauna:
			assert_bool(entry.species.is_valid()).is_true()
	assert_array(Array(SETTINGS.get_validation_errors())).is_empty()


# --- director -----------------------------------------------------------------------------


func test_spawns_herds_on_the_ground_but_never_beyond_the_cap() -> void:
	_floor()
	var director := _director(_busy_biome("deer"), Vector3(544, 0, 544))  # centre of chunk (8, 8)
	director.sync(_coords_around(Vector2i(8, 8), 1))  # 9 chunks, each with a herd of 2–4
	await _drain(director)
	assert_int(director.agents().size()).is_equal(SETTINGS.max_agents)
	for agent in director.agents():
		# On the floor (top at 0); the body may sink a centimetre or two while it settles.
		assert_float(agent.global_position.y).is_between(-0.05, 0.3)
		assert_str(String(agent.fauna.id)).is_equal("deer")


func test_never_spawns_right_next_to_the_player() -> void:
	_floor()
	var director := _director(_busy_biome("horse"), Vector3(544, 0, 544))  # chunk (8, 8)'s centre
	director.sync(_coords_around(Vector2i(8, 8), 0))
	await _drain(director)
	assert_int(director.agents().size()).is_equal(0)


func test_animals_leave_with_their_chunk_and_the_same_herd_comes_back() -> void:
	_floor()
	var director := _director(_busy_biome("alpaca"))
	var coords: Array[Vector2i] = [Vector2i(8, 9)]
	director.sync(coords)
	await _drain(director)
	var first := director.agents().size()
	assert_int(first).is_greater(0)
	var first_seed := director.agents()[0].decision_seed
	var none: Array[Vector2i] = []
	director.sync(none)  # the chunk left full detail
	assert_int(director.agents().size()).is_equal(0)
	director.sync(coords)
	await _drain(director)
	assert_int(director.agents().size()).is_equal(first)
	assert_int(director.agents()[0].decision_seed).is_equal(first_seed)


func test_ai_lod_by_distance_and_despawn_beyond_range() -> void:
	_floor()
	var director := _director(_busy_biome("donkey"))
	var coords: Array[Vector2i] = [Vector2i(8, 9)]
	director.sync(coords)
	await _drain(director)
	var agent := director.agents()[0]
	director.player.global_position = agent.global_position + Vector3(10, 0, 0)
	director.update_agents()
	assert_int(agent.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_float(agent.brain.tick_hz).is_equal(SETTINGS.full_hz)
	director.player.global_position = agent.global_position + Vector3(60, 0, 0)
	director.update_agents()
	assert_float(agent.brain.tick_hz).is_equal(SETTINGS.mid_hz)
	director.player.global_position = agent.global_position + Vector3(100, 0, 0)
	director.update_agents()
	assert_int(agent.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	director.player.global_position = agent.global_position + Vector3(130, 0, 0)
	director.update_agents()
	assert_bool(director.agents().has(agent)).is_false()


func test_no_spawns_on_water_or_where_nothing_is_loaded() -> void:
	var director := _director(_busy_biome("deer"))  # no floor at all
	director.sync(_coords_around(Vector2i(8, 8), 1))
	await _drain(director)
	assert_int(director.agents().size()).is_equal(0)
	_floor()
	GameState.water_level = 1.0  # the whole floor is under water
	var none: Array[Vector2i] = []
	director.sync(none)
	director.sync(_coords_around(Vector2i(8, 8), 1))
	await _drain(director)
	assert_int(director.agents().size()).is_equal(0)
