## Tests for the island treasures (Phase 19): where they are (deterministic, only on true
## islands of the lakes, reachable from the water, cleared of tall plants), what the director
## builds (an ancient tree with shade and night motes, rare flowers as restful as a den, an
## otter den of logs) and how a find reaches the journal, its card, the atlas and the map.
extends GdUnitTestSuite

const Places := preload("res://tests/world/places.gd")
const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")
const FOX: AnimalSpecies = preload("res://data/species/fox.tres")
const SEEDS: Array[int] = [12345, 777, 2024]

var _saved_seed: int
var _saved_minutes: float
var _reached: Array[String] = []
var _found: Array[int] = []


func before_test() -> void:
	IslandPlan.clear_cache()
	_saved_seed = GameState.world_seed
	_saved_minutes = GameState.game_minutes
	GameState.world_seed = SEEDS[0]
	_reached.clear()
	_found.clear()
	EventBus.island_reached.connect(_on_reached)
	EventBus.island_discovered.connect(_on_found)


func after_test() -> void:
	EventBus.island_reached.disconnect(_on_reached)
	EventBus.island_discovered.disconnect(_on_found)
	GameState.world_seed = _saved_seed
	GameState.game_minutes = _saved_minutes
	IslandPlan.clear_cache()


func _on_reached(key: String, _kind: int, _at: Vector3) -> void:
	_reached.append(key)


func _on_found(kind: int) -> void:
	_found.append(kind)


# Every treasure of the lake ring of [param seed_value] (cells whose centre is in the band).
func _ring(seed_value: int) -> Array[IslandTreasure]:
	var sampler := HeightSampler.new(TERRAIN, seed_value)
	var start := Places.band_start(TERRAIN, sampler, &"lakes")
	var width := Places.band_width(TERRAIN, &"lakes")
	var size := TERRAIN.islands.cell_size
	var reach := ceili((start + width) / size) + 1
	var out: Array[IslandTreasure] = []
	for cx in range(-reach, reach):
		for cz in range(-reach, reach):
			var mid := (Vector2(cx, cz) + Vector2(0.5, 0.5)) * size
			if mid.length() < start - size or mid.length() > start + width + size:
				continue
			var found := IslandPlan.treasure(
				Vector2i(cx, cz), TERRAIN.islands, sampler, seed_value, TERRAIN.sea_level
			)
			if found != null:
				out.append(found)
	return out


func test_the_settings_are_valid() -> void:
	assert_array(Array(TERRAIN.islands.get_validation_errors())).is_empty()


func test_treasures_are_deterministic_and_every_kind_appears() -> void:
	for seed_value in SEEDS:
		var first := _ring(seed_value)
		IslandPlan.clear_cache()
		var again := _ring(seed_value)
		assert_int(again.size()).is_equal(first.size())
		for i in first.size():
			assert_vector(again[i].centre).is_equal(first[i].centre)
			assert_int(again[i].kind).is_equal(first[i].kind)
		assert_int(first.size()).is_between(15, 80)  # ≈ one per 0.5 km² of the lakes
		var kinds := {}
		for found in first:
			kinds[found.kind] = true
		assert_int(kinds.size()).is_equal(3)


func test_they_stand_on_the_top_of_true_islands_of_the_lakes() -> void:
	var sampler := HeightSampler.new(TERRAIN, SEEDS[0])
	var water := TERRAIN.sea_level
	var settings := TERRAIN.islands
	for found in _ring(SEEDS[0]):
		var c := found.centre
		assert_str(String(sampler.resolver().dominant_at(c.x, c.z).id)).is_equal("lakes")
		assert_float(c.y).is_equal_approx(sampler.height_at(c.x, c.z), 1e-3)
		assert_float(c.y).is_greater(water + settings.above_water)
		for d in 24:  # water all round (at other angles than the plan's rays)
			var along := Vector2.from_angle(d * TAU / 24.0)
			var wet := false
			for r in range(4, int(settings.max_reach * 1.4), 4):
				if sampler.height_at(c.x + along.x * r, c.z + along.y * r) < water:
					wet = true
					break
			assert_bool(wet).override_failure_message("dry ray from %s" % c).is_true()


func test_each_can_be_reached_from_the_water_on_foot() -> void:
	var sampler := HeightSampler.new(TERRAIN, SEEDS[0])
	var water := TERRAIN.sea_level
	var rise := tan(deg_to_rad(FOX.max_slope_degrees)) * 2.0
	for found in _ring(SEEDS[0]):
		var c := Vector2(found.centre.x, found.centre.z)
		var walkable := 0
		for d in 8:  # some way up from the shore climbs no steeper than the fox can
			var along := Vector2.from_angle(d * TAU / 8.0)
			var ok := true
			var previous := found.centre.y
			for r in range(2, 300, 2):
				var h := sampler.height_at(c.x + along.x * r, c.y + along.y * r)
				if h < water:
					break
				if previous - h > rise:  # walking down from the top: a drop steeper than 45°
					ok = false
					break
				previous = h
			walkable += int(ok)
		assert_int(walkable).override_failure_message("cliff-bound %s" % found.centre).is_greater(0)


func test_none_outside_the_lakes() -> void:
	var sampler := HeightSampler.new(TERRAIN, SEEDS[0])
	var size := TERRAIN.islands.cell_size
	for cx in range(-6, 6):  # the meadow, forest and valley round the spawn: lakes, but no band
		for cz in range(-6, 6):
			var found := IslandPlan.treasure(
				Vector2i(cx, cz), TERRAIN.islands, sampler, SEEDS[0], TERRAIN.sea_level
			)
			assert_object(found).is_null()
	assert_float(size * 6.0).is_less(Places.band_start(TERRAIN, sampler, &"lakes"))


func test_tall_plants_are_cleared_round_a_treasure() -> void:
	var sampler := HeightSampler.new(TERRAIN, SEEDS[0])
	var tall := {}
	for biome in TERRAIN.biomes.biomes:
		for entry in biome.vegetation:
			tall[entry.type.id] = entry.type.collision_radius > 0.0
	var cleared := VegetationScatterer.new(TERRAIN.biomes)
	cleared.islands = TERRAIN.islands
	var plain := VegetationScatterer.new(TERRAIN.biomes)
	var near_cleared := 0
	var near_plain := 0
	for found in _ring(SEEDS[0]).slice(0, 8):
		near_cleared += _tall_near(found, sampler, cleared, tall)
		near_plain += _tall_near(found, sampler, plain, tall)
	assert_int(near_cleared).is_equal(0)
	assert_int(near_plain).is_greater(0)  # pines would stand there otherwise


# Tall plants within the clear radius of [param found] (the chunks round it).
func _tall_near(
	found: IslandTreasure, sampler: HeightSampler, scatterer: VegetationScatterer, tall: Dictionary
) -> int:
	var size := TERRAIN.chunk_size
	var coord := Vector2i(floori(found.centre.x / size), floori(found.centre.z / size))
	var at := Vector2(found.centre.x, found.centre.z)
	var count := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c := coord + Vector2i(dx, dz)
			var data := ChunkGenerator.generate_with(c, 0, TERRAIN, sampler, scatterer, SEEDS[0])
			for id: StringName in data.vegetation:
				if not tall.get(id, false):
					continue
				var buffer: PackedFloat32Array = data.vegetation[id]
				for n in data.vegetation_count(id):
					var o := n * VegetationScatterer.FLOATS_PER_INSTANCE
					var p := Vector2(c.x * size + buffer[o + 3], c.y * size + buffer[o + 11])
					count += int(p.distance_to(at) < TERRAIN.islands.clear_radius)
	return count


func _director(at: Vector3) -> Array:
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	player.global_position = GameState.local_position(at)
	var director: IslandDirector = auto_free(IslandDirector.new())
	director.terrain = TERRAIN
	director.player = player
	add_child(director)
	director.set_process(false)
	return [director, player]


# The first treasure of [param kind] in the ring.
func _first(kind: int) -> IslandTreasure:
	for found in _ring(SEEDS[0]):
		if found.kind == kind:
			return found
	return null


func test_the_director_builds_each_treasure_near_and_frees_it_far() -> void:
	for kind in 3:
		var found := _first(kind)
		var made := _director(found.centre + Vector3(60, 0, 0))
		var director: IslandDirector = made[0]
		var player: Node3D = made[1]
		director.refresh()
		var root := director.treasure_root(found.cell)
		assert_object(root).is_not_null()
		assert_bool(root.is_in_group(FloatingOrigin.SHIFTABLE_GROUP)).is_true()
		assert_vector(root.global_position).is_equal_approx(
			GameState.local_position(found.centre), Vector3.ONE * 1e-3
		)
		match kind:
			IslandPlan.Treasure.ANCIENT_TREE:
				var tree: Node3D = root.get_node("AncientTree")
				assert_float(tree.scale.x).is_equal(TERRAIN.islands.tree_scale)
				var trunk: StaticBody3D = root.get_node("Trunk")
				assert_int(trunk.collision_layer).is_equal(1)  # the fox walks round it
				assert_object(root.get_node_or_null("Motes")).is_not_null()
			IslandPlan.Treasure.RARE_FLOWERS:
				var flowers: MultiMeshInstance3D = root.get_node("RareFlowers")
				assert_int(flowers.multimesh.instance_count).is_equal(TERRAIN.islands.flowers)
				var layout := IslandDirector.flower_layout(
					found, TERRAIN.islands, HeightSampler.new(TERRAIN, SEEDS[0])
				)
				var places: PackedVector3Array = layout[0]
				for p in places:  # on the ground of the ring round the top
					assert_float(Vector2(p.x, p.z).length()).is_less_equal(
						TERRAIN.islands.flower_radius
					)
				var colours: PackedColorArray = layout[1]
				var kinds := {}
				for colour in colours:
					assert_bool(TERRAIN.islands.flower_colors.has(colour)).is_true()
					kinds[colour] = true
				assert_int(kinds.size()).is_equal(TERRAIN.islands.flower_colors.size())
				for biome in TERRAIN.biomes.biomes:  # colours found nowhere else
					for entry in biome.vegetation:
						(
							assert_bool(
								TERRAIN.islands.flower_colors.has(entry.type.procedural_color)
							)
							. is_false()
						)
			IslandPlan.Treasure.OTTER_DEN:
				var den: Node3D = root.get_node("OtterDen")
				assert_int(den.get_child_count()).is_equal(TERRAIN.islands.den_logs)
		player.global_position += Vector3(TERRAIN.islands.free_radius + 50.0, 0, 0)
		director.refresh()
		assert_array(director.built_cells()).is_empty()
		director.free()
		player.free()


func test_the_motes_glow_only_at_night() -> void:
	var found := _first(IslandPlan.Treasure.ANCIENT_TREE)
	var director: IslandDirector = _director(found.centre)[0]
	GameState.game_minutes = 12.0 * 60.0
	director.refresh()
	var motes: GPUParticles3D = director.treasure_root(found.cell).get_node("Motes")
	assert_bool(motes.emitting).is_false()
	GameState.game_minutes = 21.0 * 60.0
	director.refresh()
	assert_bool(motes.emitting).is_true()


func test_the_tree_shades_and_the_flowers_are_restful() -> void:
	var tree := _first(IslandPlan.Treasure.ANCIENT_TREE)
	var flowers := _first(IslandPlan.Treasure.RARE_FLOWERS)
	var made := _director(tree.centre)
	var director: IslandDirector = made[0]
	var player: Node3D = made[1]
	director.refresh()
	var under := GameState.local_position(tree.centre + Vector3(2, 0, 1))
	assert_bool(director.is_shaded(under)).is_true()
	(
		assert_bool(director.is_shaded(under + Vector3(TERRAIN.islands.tree_shade + 2.0, 0, 0)))
		. is_false()
	)
	assert_bool(director.is_cosy(under)).is_false()  # a tree, not flowers
	assert_bool(director in get_tree().get_nodes_in_group(WorldStreamer.SHADE_GROUP)).is_true()
	assert_bool(director in get_tree().get_nodes_in_group(Rester.COSY_GROUP)).is_true()
	player.global_position = GameState.local_position(flowers.centre)
	director.refresh()
	(
		assert_bool(director.is_cosy(GameState.local_position(flowers.centre + Vector3(1, 0, 2))))
		. is_true()
	)


func test_reaching_a_treasure_tells_the_journal_once() -> void:
	var found := _first(IslandPlan.Treasure.RARE_FLOWERS)
	var made := _director(found.centre + Vector3(TERRAIN.islands.discover_radius + 20.0, 0, 0))
	var director: IslandDirector = made[0]
	var player: Node3D = made[1]
	var tracker: EncounterTracker = auto_free(EncounterTracker.new())
	tracker.settings = JOURNAL
	tracker.player = player
	add_child(tracker)
	tracker.set_process(false)
	director.refresh()
	assert_array(_reached).is_empty()  # built, but not reached yet
	player.global_position = GameState.local_position(found.centre + Vector3(3, 0, 0))
	director.refresh()
	director.refresh()
	assert_array(_reached).is_equal([found.key(), found.key()] as Array[String])
	assert_array(_found).is_equal([IslandPlan.Treasure.RARE_FLOWERS] as Array[int])  # once
	assert_int(tracker.journal.island_count()).is_equal(1)
	assert_vector(tracker.journal.island_positions()[0]).is_equal(found.centre)


func test_the_director_works_out_one_new_cell_per_lookup() -> void:
	var found: IslandTreasure = _ring(SEEDS[0])[0]
	IslandPlan.clear_cache()
	var director: IslandDirector = _director(found.centre)[0]
	var r := TERRAIN.islands.build_radius
	var size := TERRAIN.islands.cell_size
	var cells := 0
	for cx in range(floori((found.centre.x - r) / size), floori((found.centre.x + r) / size) + 1):
		for cz in range(
			floori((found.centre.z - r) / size), floori((found.centre.z + r) / size) + 1
		):
			cells += 1
	assert_int(cells).is_greater(1)
	director.refresh()
	assert_int(_cached_round(found, r, size)).is_equal(1)  # one new cell per lookup
	for step in cells:
		director.refresh()
	assert_object(director.treasure_root(found.cell)).is_not_null()  # all worked out by then
	var cached := 0
	for cx in range(floori((found.centre.x - r) / size), floori((found.centre.x + r) / size) + 1):
		for cz in range(
			floori((found.centre.z - r) / size), floori((found.centre.z + r) / size) + 1
		):
			cached += int(IslandPlan.is_cached(Vector2i(cx, cz), SEEDS[0]))
	assert_int(cached).is_equal(cells)


func test_the_journal_saves_the_islands_and_loads_older_journals() -> void:
	var journal := AnimalJournal.new()
	assert_bool(journal.find_island("12,3", 1, 900.0, Vector3(3600, 2, 900))).is_true()
	assert_bool(journal.find_island("12,3", 1, 1900.0, Vector3(3600, 2, 900))).is_false()
	assert_bool(journal.find_island("-4,15", 0, 2400.0, Vector3(-1200, 4, 4500))).is_true()
	var copy := AnimalJournal.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(journal.to_dict())))
	assert_int(copy.island_count()).is_equal(2)
	assert_bool(copy.has_island("-4,15")).is_true()
	assert_bool(copy.has_island("0,0")).is_false()
	assert_array(Array(copy.island_positions())).contains([Vector3(3600, 2, 900)])
	copy.from_dict({"version": 2, "seen": {}, "biomes": {}})  # before the islands
	assert_int(copy.island_count()).is_equal(0)


func test_a_find_gets_its_card_and_the_atlas_counts_it() -> void:
	var card: DiscoveryCard = auto_free(DiscoveryCard.new())
	card.settings = preload("res://data/ui/discovery_card.tres")
	card.journal = JOURNAL
	card.terrain = TERRAIN
	add_child(card)
	EventBus.island_discovered.emit(IslandPlan.Treasure.ANCIENT_TREE)
	card.enqueue_island(7)  # ignored
	await get_tree().process_frame
	assert_bool(card.showing_island).is_true()
	assert_str(card.shown_name()).is_equal("An ancient tree")
	assert_str((card.find_child("New", true, false) as Label).text).is_equal("Island treasure!")
	assert_int(card.waiting()).is_equal(0)
	var journal := AnimalJournal.new()
	journal.find_island("1,2", 2, 60.0, Vector3.ZERO)
	var atlas: BiomeAtlasPage = auto_free(BiomeAtlasPage.new())
	add_child(atlas)
	atlas.refresh(TERRAIN.biomes, journal, JOURNAL, null)
	assert_str(atlas.islands_text()).is_equal("Island treasures found: 1")


func _cached_round(found: IslandTreasure, r: float, size: float) -> int:
	var cached := 0
	for cx in range(floori((found.centre.x - r) / size), floori((found.centre.x + r) / size) + 1):
		for cz in range(
			floori((found.centre.z - r) / size), floori((found.centre.z + r) / size) + 1
		):
			cached += int(IslandPlan.is_cached(Vector2i(cx, cz), SEEDS[0]))
	return cached
