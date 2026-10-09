## Tests for the rural hamlets (Phase 16, ADR-007): where they are (deterministic, only on flat,
## dry ground fully inside their biomes, rare), how they are laid out (no piece overlaps, a pen by
## the stable), the clearings in the vegetation, and the director that builds and frees them.
extends GdUnitTestSuite

const TERRAIN: TerrainSettings = preload("res://data/world/terrain_settings.tres")
const SEED: int = 12345

var _sampler: HeightSampler
var _saved_seed: int


func before_test() -> void:
	HamletPlan.clear_cache()
	_sampler = HeightSampler.new(TERRAIN, SEED)
	_saved_seed = GameState.world_seed
	GameState.world_seed = SEED


func after_test() -> void:
	GameState.world_seed = _saved_seed
	HamletPlan.clear_cache()


func _all() -> Array[HamletLayout]:
	var out: Array[HamletLayout] = []
	for cx in range(-6, 6):
		for cz in range(-6, 6):
			var hamlet := HamletPlan.layout(
				Vector2i(cx, cz), TERRAIN.hamlets, _sampler, SEED, TERRAIN.sea_level
			)
			if hamlet != null:
				out.append(hamlet)
	return out


func test_the_settings_are_valid() -> void:
	assert_array(Array(TERRAIN.hamlets.get_validation_errors())).is_empty()


func test_hamlets_are_deterministic_and_rare() -> void:
	var first := _all()
	HamletPlan.clear_cache()
	var again := _all()
	assert_int(again.size()).is_equal(first.size())
	for i in first.size():
		assert_vector(again[i].centre).is_equal(first[i].centre)
		assert_array(again[i].ids).is_equal(first[i].ids)
	var area := 144 * pow(TERRAIN.hamlets.cell_size / 1000.0, 2)  # km²
	assert_float(area / first.size()).is_between(5.0, 40.0)  # one per 5–40 km²
	HamletPlan.clear_cache()
	var other := HamletPlan.near(
		0, 0, 9000, TERRAIN.hamlets, HeightSampler.new(TERRAIN, 777), 777, TERRAIN.sea_level
	)
	assert_bool(other.size() > 0 and other[0].centre != first[0].centre).is_true()  # another world


func test_they_stand_on_flat_dry_ground_inside_their_biome() -> void:
	var resolver := _sampler.resolver()
	for hamlet in _all():
		assert_bool(TERRAIN.hamlets.biomes.has(hamlet.biome)).is_true()
		assert_str(String(resolver.dominant_at(hamlet.centre.x, hamlet.centre.z).id)).is_equal(
			String(hamlet.biome)
		)
		for i in hamlet.size():
			var p := hamlet.positions[i]
			assert_float(p.y).is_equal_approx(_sampler.height_at(p.x, p.z), 1e-3)  # on the ground
			assert_float(p.y).is_greater(TERRAIN.sea_level + TERRAIN.hamlets.above_water)
		assert_float(absf(hamlet.positions[1].y - hamlet.centre.y)).is_less(4.0)  # gentle


func test_no_piece_overlaps_another_and_the_stable_has_a_pen() -> void:
	var with_pen := 0
	for hamlet in _all():
		var houses := 0
		for i in hamlet.size():
			houses += int(TERRAIN.hamlets.house_ids.has(hamlet.ids[i]))
			for j in range(i + 1, hamlet.size()):
				if hamlet.ids[i] == &"fence" and hamlet.ids[j] == &"fence":
					continue  # panels of the pen touch each other
				var gap := (
					Vector2(
						hamlet.positions[i].x - hamlet.positions[j].x,
						hamlet.positions[i].z - hamlet.positions[j].z
					)
					. length()
				)
				assert_float(gap).is_greater_equal(hamlet.radii[i] + hamlet.radii[j] - 0.01)
		assert_int(houses).is_between(TERRAIN.hamlets.houses.x - 1, TERRAIN.hamlets.houses.y)
		assert_str(String(hamlet.ids[0])).is_equal("well")
		if hamlet.pen != Vector3.INF:
			with_pen += 1
			assert_int(hamlet.ids.count(&"fence")).is_equal(16)
	assert_int(with_pen).is_greater(0)


func _chunk_with(coord: Vector2i, hamlets: bool) -> ChunkData:
	var scatterer := VegetationScatterer.new(TERRAIN.biomes)
	scatterer.hamlets = TERRAIN.hamlets if hamlets else null
	return ChunkGenerator.generate_with(coord, 0, TERRAIN, _sampler, scatterer, SEED)


func test_plants_are_cleared_from_hamlets_and_untouched_elsewhere() -> void:
	var hamlet: HamletLayout = _all()[0]
	var coord := Vector2i(
		floori(hamlet.centre.x / TERRAIN.chunk_size), floori(hamlet.centre.z / TERRAIN.chunk_size)
	)
	var size := TERRAIN.chunk_size
	var tall := {}
	for biome in TERRAIN.biomes.biomes:
		for entry in biome.vegetation:
			tall[entry.type.id] = entry.type.collision_radius > 0.0
	var checked := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c := coord + Vector2i(dx, dz)
			var data := _chunk_with(c, true)
			for id: StringName in data.vegetation:
				var buffer: PackedFloat32Array = data.vegetation[id]
				for n in data.vegetation_count(id):
					var o := n * VegetationScatterer.FLOATS_PER_INSTANCE
					var x := c.x * size + buffer[o + 3]
					var z := c.y * size + buffer[o + 11]
					checked += 1
					for i in hamlet.size():
						var d := (
							Vector2(x - hamlet.positions[i].x, z - hamlet.positions[i].z).length()
						)
						assert_float(d).is_greater_equal(hamlet.radii[i])  # nothing on a piece
					if tall.get(id, false):  # drops (apples, berries) are not plants of their own
						var from_well := Vector2(x - hamlet.centre.x, z - hamlet.centre.z).length()
						(
							assert_float(from_well)
							. override_failure_message(String(id))
							. is_greater_equal(TERRAIN.hamlets.clear_radius)
						)
	assert_int(checked).is_greater(50)
	var far := coord + Vector2i(40, 0)  # 2.5 km away
	assert_that(_chunk_with(far, true).vegetation).is_equal(_chunk_with(far, false).vegetation)


func test_the_director_builds_nearby_hamlets_and_frees_them_when_far() -> void:
	var hamlet: HamletLayout = (
		HamletPlan.near(0, 0, 2000, TERRAIN.hamlets, _sampler, SEED, TERRAIN.sea_level)[0]
	)
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	player.global_position = GameState.local_position(hamlet.centre + Vector3(30, 0, 0))
	var director: HamletDirector = auto_free(HamletDirector.new())
	director.terrain = TERRAIN
	director.player = player
	add_child(director)
	director.set_process(false)
	director.refresh()
	assert_array(director.built_cells()).contains([hamlet.cell])
	director.build_all_now()
	var root := director.hamlet_root(hamlet.cell)
	assert_int(root.get_child_count()).is_equal(hamlet.size())
	assert_bool(root.is_in_group(FloatingOrigin.SHIFTABLE_GROUP)).is_true()
	assert_vector(root.global_position).is_equal_approx(
		GameState.local_position(hamlet.centre), Vector3.ONE * 1e-3
	)
	var solid := 0
	for i in hamlet.size():
		solid += int(TERRAIN.hamlets.piece(hamlet.ids[i]).solid)
	var bodies := root.find_children("*", "StaticBody3D", true, false)
	assert_int(bodies.size()).is_equal(solid)
	for body: StaticBody3D in bodies:
		assert_int(body.collision_layer).is_equal(1)  # the world: the fox walks round them
	player.global_position += Vector3(2000, 0, 0)
	director.refresh()
	assert_array(director.built_cells()).is_empty()
	assert_int(director.pending()).is_equal(0)


func test_a_site_by_the_water_or_on_a_slope_is_refused() -> void:
	var settings := TERRAIN.hamlets
	var hamlet: HamletLayout = _all()[0]
	var ok := HamletPlan._flat_and_dry(
		hamlet.centre.x, hamlet.centre.z, settings, _sampler, TERRAIN.sea_level
	)
	assert_bool(ok).is_true()
	# The lake nearest to the spawn (≈ 250, −720; see test_ducks.gd): its shore is wet.
	(
		assert_bool(HamletPlan._flat_and_dry(250.0, -690.0, settings, _sampler, TERRAIN.sea_level))
		. is_false()
	)
	var steep: HamletSettings = settings.duplicate()
	steep.max_slope = 0.5  # nothing is that flat
	var flat := HamletPlan._flat_and_dry(
		hamlet.centre.x, hamlet.centre.z, steep, _sampler, TERRAIN.sea_level
	)
	assert_bool(flat).is_false()
