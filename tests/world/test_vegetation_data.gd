## Tests for [VegetationType] / [VegetationEntry] validation and the per-biome tables.
extends GdUnitTestSuite

const TABLE_PATH: String = "res://data/biomes/biome_table.tres"
const TYPES_DIR: String = "res://data/vegetation"

var _table: BiomeTable


func before() -> void:
	_table = load(TABLE_PATH)


func _biome(id: StringName) -> BiomeDefinition:
	for biome in _table.biomes:
		if biome.id == id:
			return biome
	return null


## Summed density per 100 m² of entries whose type id starts with [param prefix].
func _density(biome_id: StringName, prefix: String) -> float:
	var total := 0.0
	for entry in _biome(biome_id).vegetation:
		if String(entry.type.id).begins_with(prefix):
			total += entry.density
	return total


func test_every_type_is_valid_and_points_at_a_model_or_a_procedural_shape() -> void:
	var files := DirAccess.get_files_at(TYPES_DIR)
	assert_int(files.size()).is_greater(10)
	for file in files:
		var type := load(TYPES_DIR.path_join(file)) as VegetationType
		assert_array(Array(type.get_validation_errors())).is_empty()
		if type.procedural_shape != &"":
			assert_object(type.scene).is_null()
			continue
		assert_str(type.scene.resource_path).starts_with("res://assets/environment/nature/")


func test_procedural_meshes_stand_on_their_origin_and_have_their_size() -> void:
	# Footprint across (m): bushes and fruit ≈ 1 m (scaled per instance), reed tufts narrower,
	# lily pads ≈ 0.5 m.
	var across := {
		&"reeds": Vector2(0.3, 0.9),
		&"cattails": Vector2(0.3, 0.9),
		&"water_lily": Vector2(0.4, 0.6),
		&"water_lily_flower": Vector2(0.4, 0.6),
	}
	for shape: StringName in ProceduralMeshes.SHAPES:
		var aabb := ProceduralMeshes.build(shape).get_aabb()
		assert_float(aabb.position.y).override_failure_message(String(shape)).is_between(
			-0.02, 0.02
		)
		var span: Vector2 = across.get(shape, Vector2(0.8, 1.3))
		(
			assert_float(maxf(aabb.size.x, aabb.size.z))
			. override_failure_message(String(shape))
			. is_between(span.x, span.y)
		)


func test_every_biome_has_vegetation_and_the_table_stays_valid() -> void:
	assert_array(Array(_table.get_validation_errors())).is_empty()
	for biome in _table.biomes:
		assert_int(biome.vegetation.size()).is_greater(4)


func test_only_aquatic_plants_may_grow_underwater() -> void:
	# Reeds and cattails stand in the shallows, water lilies float (Phase 14); everything else
	# stays above the waterline.
	var aquatic: Array[StringName] = [&"reeds", &"cattails", &"water_lily", &"water_lily_flower"]
	for biome in _table.biomes:
		for entry in biome.vegetation:
			if aquatic.has(entry.type.id):
				continue
			(
				assert_float(entry.min_height)
				. override_failure_message(String(entry.type.id))
				. is_greater_equal(0.0)
			)
		for entry in biome.vegetation:
			if entry.type.float_on_water:
				assert_float(entry.max_height).is_less(0.0)  # only over water


func test_forest_is_the_densest_in_trees() -> void:
	var forest := _density(&"forest", "tree_")
	for biome in _table.biomes:
		if biome.id != &"forest":
			assert_float(forest).is_greater(3.0 * _density(biome.id, "tree_"))


func test_meadow_has_the_most_flowers() -> void:
	var meadow := _density(&"meadow", "flower_")
	for biome in _table.biomes:
		if biome.id != &"meadow":
			assert_float(meadow).is_greater(_density(biome.id, "flower_"))


func test_hills_have_the_most_rocks() -> void:
	var hills := _density(&"hills", "rock_")
	for biome in _table.biomes:
		if biome.id != &"hills":
			assert_float(hills).is_greater(_density(biome.id, "rock_"))


func test_valley_reeds_only_grow_at_the_waterline() -> void:
	for entry in _biome(&"river_valley").vegetation:
		if entry.type.id == &"grass_leafsLarge":
			assert_float(entry.max_height).is_less_equal(2.0)


func test_only_trees_and_large_rocks_collide() -> void:
	for file in DirAccess.get_files_at(TYPES_DIR):
		var type := load(TYPES_DIR.path_join(file)) as VegetationType
		var should := (
			String(type.id).begins_with("tree_") or String(type.id).begins_with("rock_large")
		)
		assert_bool(type.has_collision()).override_failure_message(String(type.id)).is_equal(should)


func test_small_plants_are_near_only_and_trees_are_not() -> void:
	for file in DirAccess.get_files_at(TYPES_DIR):
		var type := load(TYPES_DIR.path_join(file)) as VegetationType
		if String(type.id).begins_with("tree_"):
			assert_bool(type.near_only).is_false()  # visible far away: no pop-in
		if String(type.id).begins_with("grass") or String(type.id).begins_with("flower_"):
			assert_bool(type.near_only).is_true()


func test_invalid_entries_are_rejected() -> void:
	var entry := VegetationEntry.new()
	assert_bool(entry.is_valid()).is_false()
	var type := VegetationType.new()
	type.collision_radius = 0.2
	assert_array(Array(type.get_validation_errors())).contains(
		["collision_height must be > 0 when collision_radius is set"]
	)
