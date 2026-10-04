## Tests for tree / large-rock collision: shapes, rays, LOD filtering and the animal.
extends GdUnitTestSuite

const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const MATERIAL_PATH: String = "res://data/world/terrain_material.tres"
const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const SEED: int = 12345
const FOREST := Vector2i(17, 2)
const STREAMING: StreamingSettings = preload("res://data/world/streaming_settings.tres")

var _settings: TerrainSettings
var _scatterer: VegetationScatterer
var _library: VegetationLibrary


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_scatterer = VegetationScatterer.new(_settings.biomes)
	_library = VegetationLibrary.new(_settings.biomes)


func _gen(coord: Vector2i, lod: int = 0) -> ChunkData:
	return ChunkGenerator.generate_with(
		coord, lod, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED
	)


## Chunk placed at the scene origin (positions below are chunk-local).
func _chunk(data: ChunkData) -> TerrainChunk:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	chunk.apply(data, load(MATERIAL_PATH), _library)
	return chunk


func _instances(data: ChunkData, id: StringName) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var b: PackedFloat32Array = data.vegetation.get(id, PackedFloat32Array())
	for o in range(0, b.size(), VegetationScatterer.FLOATS_PER_INSTANCE):
		var basis := Basis(
			Vector3(b[o], b[o + 4], b[o + 8]),
			Vector3(b[o + 1], b[o + 5], b[o + 9]),
			Vector3(b[o + 2], b[o + 6], b[o + 10])
		)
		out.append(Transform3D(basis, Vector3(b[o + 3], b[o + 7], b[o + 11])))
	return out


func _ray(node: Node3D, x: float, z: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -300.0, z))
	return node.get_world_3d().direct_space_state.intersect_ray(query)


func _collidable_count(data: ChunkData) -> int:
	var total := 0
	for id: StringName in data.vegetation:
		if _library.collision_for(id).x > 0.0:
			total += data.vegetation_count(id)
	return total


func test_one_shape_per_tree_and_large_rock() -> void:
	var data := _gen(FOREST)
	var chunk := _chunk(data)
	assert_int(chunk.obstacle_count()).is_equal(_collidable_count(data))
	assert_int(chunk.obstacle_count()).is_greater(10)


func test_ray_hits_the_top_of_a_trunk() -> void:
	var data := _gen(FOREST)
	var chunk := _chunk(data)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tree := _instances(data, &"tree_detailed")[0]
	var size := _library.collision_for(&"tree_detailed")
	var hit := _ray(chunk, tree.origin.x, tree.origin.z)
	var scale := tree.basis.get_scale().y
	assert_float((hit["position"] as Vector3).y).is_equal_approx(
		tree.origin.y + size.y * scale, 0.05
	)


func test_ray_through_grass_reaches_the_ground() -> void:
	var data := ChunkGenerator.generate_with(
		Vector2i(3, 3), 0, _settings, HeightSampler.new(_settings, SEED), _scatterer, SEED
	)
	var chunk := _chunk(data)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var grass := _instances(data, &"grass")[5]
	var hit := _ray(chunk, grass.origin.x, grass.origin.z)
	assert_float((hit["position"] as Vector3).y).is_equal_approx(grass.origin.y, 0.1)


func test_coarse_chunks_have_no_obstacles() -> void:
	var chunk := _chunk(_gen(FOREST, 1))
	assert_int(chunk.obstacle_count()).is_equal(0)


func test_reapply_reuses_obstacle_shapes() -> void:
	var chunk := _chunk(_gen(FOREST))
	var shapes := chunk.get_node("%Body").get_child_count()
	chunk.apply(_gen(Vector2i(3, 3)), load(MATERIAL_PATH), _library)
	chunk.apply(_gen(FOREST), load(MATERIAL_PATH), _library)
	assert_int(chunk.get_node("%Body").get_child_count()).is_equal(shapes)
	chunk.reset()
	assert_int(chunk.obstacle_count()).is_equal(0)


func test_animal_cannot_walk_through_a_tree() -> void:
	var data := _gen(FOREST)
	var chunk := _chunk(data)
	var tree := _instances(data, &"tree_detailed")[0]
	var radius := _library.collision_for(&"tree_detailed").x * tree.basis.get_scale().y
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	var start := tree.origin + Vector3(0.0, 0.0, 4.0)
	start.y = (VegetationScatterer.surface_at(data, start.x, start.z)[0] as float) + 0.3
	animal.position = start
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	for i in 30:
		await get_tree().physics_frame
	animal.movement.move_input = Vector2(0.0, -1.0)  # forward = -Z, straight at the trunk
	var closest := INF
	for i in 180:
		await get_tree().physics_frame
		closest = minf(
			closest,
			(
				Vector2(
					animal.global_position.x - tree.origin.x,
					animal.global_position.z - tree.origin.z
				)
				. length()
			)
		)
	assert_float(closest).is_greater(radius * 0.9)
	assert_float(animal.global_position.z).is_greater(tree.origin.z)  # never got past it
	assert_object(chunk).is_not_null()


# --- reserved capacity (Phase 11: no physics objects created on a cold chunk's first apply) ---


func test_a_reserved_chunk_creates_no_shapes_when_applied() -> void:
	var streaming := STREAMING
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	assert_bool(chunk.reserve(streaming.food_shape_reserve, streaming.obstacle_reserve)).is_true()
	var reserved := chunk.reserved()
	assert_that(reserved).is_equal(
		Vector2i(streaming.food_shape_reserve, streaming.obstacle_reserve)
	)
	var data := _gen(FOREST)
	chunk.apply(data, load(MATERIAL_PATH), _library)
	assert_that(chunk.reserved()).is_equal(reserved)  # nothing new was created
	assert_int(chunk.obstacle_count()).is_equal(_collidable_count(data))
	# The body went back into the physics space: trunks and ground still collide.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tree := _instances(data, &"tree_detailed")[0]
	var hit := _ray(chunk, tree.origin.x, tree.origin.z)
	assert_float((hit["position"] as Vector3).y).is_greater(tree.origin.y + 0.5)
	assert_bool(_ray(chunk, 1.0, 1.0).is_empty()).is_false()


func test_the_reserve_can_be_spread_over_calls() -> void:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	assert_bool(chunk.reserve(10, 5, 6)).is_false()
	assert_that(chunk.reserved()).is_equal(Vector2i(6, 0))
	assert_bool(chunk.reserve(10, 5, 6)).is_false()
	assert_that(chunk.reserved()).is_equal(Vector2i(10, 2))
	assert_bool(chunk.reserve(10, 5, 6)).is_true()
	assert_that(chunk.reserved()).is_equal(Vector2i(10, 5))
	assert_bool(chunk.reserve(10, 5, 6)).is_true()  # complete: nothing more


func test_the_reserve_covers_wooded_chunks() -> void:
	var streaming := STREAMING
	var most := Vector2i.ZERO
	for i in 24:
		var coord := Vector2i(10 + i, (i % 3) - 1)  # through the forest band along +X
		var chunk := _chunk(_gen(coord))
		most = Vector2i(maxi(most.x, chunk.food_count()), maxi(most.y, chunk.obstacle_count()))
	assert_int(most.x).is_less_equal(streaming.food_shape_reserve)
	assert_int(most.y).is_less_equal(streaming.obstacle_reserve)
	assert_int(most.y).is_greater(10)  # the sample really is wooded
