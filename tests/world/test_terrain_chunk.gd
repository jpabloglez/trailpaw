## Tests for [TerrainChunk]: mesh upload, height-map collision and pool reuse.
extends GdUnitTestSuite

const CHUNK_SCENE: String = "res://scenes/world/terrain_chunk.tscn"
const SETTINGS_PATH: String = "res://data/world/terrain_settings.tres"
const MATERIAL_PATH: String = "res://data/world/terrain_placeholder_material.tres"
const SEED: int = 12345

var _settings: TerrainSettings
var _material: Material
var _sampler: HeightSampler


func before() -> void:
	_settings = load(SETTINGS_PATH)
	_material = load(MATERIAL_PATH)
	_sampler = HeightSampler.new(_settings, SEED)


func _make_chunk(coord: Vector2i, lod: int) -> TerrainChunk:
	var chunk: TerrainChunk = auto_free(load(CHUNK_SCENE).instantiate())
	add_child(chunk)
	_place_and_apply(chunk, coord, lod)
	return chunk


func _place_and_apply(chunk: TerrainChunk, coord: Vector2i, lod: int) -> void:
	chunk.position = Vector3(coord.x, 0.0, coord.y) * _settings.chunk_size
	chunk.apply(ChunkGenerator.generate(coord, lod, _settings, SEED), _material)


## Casts a vertical ray at world (x, z); returns the hit height or NAN on a miss.
func _ray_height(chunk: Node3D, x: float, z: float) -> float:
	var space := chunk.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 500.0, z), Vector3(x, -500.0, z))
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


func _await_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_lod0_settings_spacing_matches_heightmap() -> void:
	assert_float(_settings.step_for_lod(0)).is_equal(TerrainSettings.COLLISION_STEP)


func test_apply_uploads_mesh_with_material() -> void:
	var chunk := _make_chunk(Vector2i(1, 2), 0)
	var mesh := (chunk.get_node("%Mesh") as MeshInstance3D).mesh as ArrayMesh
	var res := _settings.resolution_for_lod(0)
	assert_int(mesh.get_surface_count()).is_equal(1)
	assert_int(mesh.surface_get_array_len(0)).is_equal(res * res)
	assert_object(mesh.surface_get_material(0)).is_same(_material)
	var aabb := mesh.get_aabb()
	assert_float(aabb.size.x).is_equal_approx(_settings.chunk_size, 1e-3)
	assert_float(aabb.size.z).is_equal_approx(_settings.chunk_size, 1e-3)
	assert_bool(chunk.visible).is_true()


func test_collision_matches_sampled_heights() -> void:
	var coord := Vector2i(2, -1)
	var chunk := _make_chunk(coord, 0)
	assert_bool(chunk.has_collision()).is_true()
	await _await_physics()
	var origin := Vector2(coord) * _settings.chunk_size
	var probes: Array[Vector2] = [Vector2(0, 0), Vector2(17, 40), Vector2(63, 5), Vector2(32, 32)]
	for p: Vector2 in probes:
		var x := origin.x + p.x
		var z := origin.y + p.y
		assert_float(_ray_height(chunk, x, z)).is_equal_approx(_sampler.height_at(x, z), 0.05)


func test_lod1_has_no_collision() -> void:
	var chunk := _make_chunk(Vector2i(0, 0), 1)
	assert_bool(chunk.has_collision()).is_false()
	await _await_physics()
	assert_bool(is_nan(_ray_height(chunk, 10.0, 10.0))).is_true()


func test_chunk_can_be_reset_and_reused() -> void:
	var chunk := _make_chunk(Vector2i(0, 0), 0)
	chunk.reset()
	assert_bool(chunk.visible).is_false()
	assert_bool(chunk.has_collision()).is_false()
	assert_int(chunk.lod).is_equal(-1)
	var coord := Vector2i(-3, 4)
	_place_and_apply(chunk, coord, 0)
	assert_object(chunk.coord).is_equal(coord)
	await _await_physics()
	var x := coord.x * _settings.chunk_size + 20.0
	var z := coord.y * _settings.chunk_size + 9.0
	assert_float(_ray_height(chunk, x, z)).is_equal_approx(_sampler.height_at(x, z), 0.05)
