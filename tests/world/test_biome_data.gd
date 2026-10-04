## Tests for [BiomeDefinition] / [BiomeTable] validation and the shipped biome data.
extends GdUnitTestSuite

const TABLE_PATH: String = "res://data/biomes/biome_table.tres"
const EXPECTED_ORDER: Array[StringName] = [
	&"meadow", &"forest", &"river_valley", &"wetland", &"hills"
]

var _table: BiomeTable


func before() -> void:
	_table = load(TABLE_PATH)


func test_table_is_valid() -> void:
	assert_array(Array(_table.get_validation_errors())).is_empty()


func test_bands_are_in_the_designed_order_and_cycle() -> void:
	var ids: Array[StringName] = []
	for biome in _table.biomes:
		ids.append(biome.id)
	assert_array(ids).is_equal(EXPECTED_ORDER)
	assert_bool(_table.cycle).is_true()


func test_every_biome_is_valid_with_a_display_name() -> void:
	for biome in _table.biomes:
		assert_array(Array(biome.get_validation_errors())).is_empty()
		assert_str(biome.display_name).is_not_empty()


func test_bands_are_about_800_m_wide() -> void:
	for biome in _table.biomes:
		assert_float(biome.band_width).is_between(600.0, 1000.0)
	# Five 800 m bands since the wetland (ADR-006): a 4 km cycle.
	assert_float(_table.sequence_length()).is_equal_approx(4000.0, 400.0)


func test_blend_fits_inside_the_narrowest_band() -> void:
	assert_float(_table.blend_width).is_less_equal(_table.narrowest_band())


func test_unconfigured_biome_is_invalid() -> void:
	assert_bool(BiomeDefinition.new().is_valid()).is_false()


func test_duplicate_ids_are_rejected() -> void:
	var table := _table.duplicate() as BiomeTable
	var biomes: Array[BiomeDefinition] = _table.biomes.duplicate()
	biomes.append(_table.biomes[0])
	table.biomes = biomes
	assert_bool(table.is_valid()).is_false()


func test_blend_wider_than_a_band_is_rejected() -> void:
	var table := _table.duplicate() as BiomeTable
	table.blend_width = _table.narrowest_band() + 1.0
	assert_bool(table.is_valid()).is_false()


func test_river_valley_sits_lowest_and_hills_highest() -> void:
	var offsets := {}
	for biome in _table.biomes:
		offsets[biome.id] = biome.height_offset
	assert_float(offsets[&"river_valley"]).is_less(offsets[&"meadow"])
	assert_float(offsets[&"hills"]).is_greater(offsets[&"meadow"])


func test_hills_do_not_look_like_meadow() -> void:
	var by_id := {}
	for biome in _table.biomes:
		by_id[biome.id] = biome
	var meadow: BiomeDefinition = by_id[&"meadow"]
	var hills: BiomeDefinition = by_id[&"hills"]
	# Distinct palettes: clearly different colours, not two similar greens.
	var diff_a := Vector3(
		meadow.ground_color_a.r - hills.ground_color_a.r,
		meadow.ground_color_a.g - hills.ground_color_a.g,
		meadow.ground_color_a.b - hills.ground_color_a.b
	)
	assert_float(diff_a.length()).is_greater(0.12)
	# Clearly taller and rougher.
	assert_float(hills.height_offset - meadow.height_offset).is_greater_equal(5.0)
	assert_float(hills.ridged_scale).is_greater(4.0 * meadow.ridged_scale)
