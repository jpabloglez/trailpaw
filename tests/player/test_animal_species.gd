## Tests for [AnimalSpecies] validation and the placeholder species data.
extends GdUnitTestSuite

const PLACEHOLDER_PATH: String = "res://data/species/placeholder.tres"


func _valid_species() -> AnimalSpecies:
	return load(PLACEHOLDER_PATH).duplicate() as AnimalSpecies


func test_placeholder_loads_and_is_valid() -> void:
	var species := load(PLACEHOLDER_PATH) as AnimalSpecies
	assert_object(species).is_not_null()
	assert_array(Array(species.get_validation_errors())).is_empty()
	assert_bool(species.is_valid()).is_true()


func test_placeholder_gait_speeds_are_ordered() -> void:
	var species := load(PLACEHOLDER_PATH) as AnimalSpecies
	assert_float(species.walk_speed).is_less(species.trot_speed)
	assert_float(species.trot_speed).is_less(species.run_speed)


func test_unconfigured_species_is_invalid() -> void:
	assert_bool(AnimalSpecies.new().is_valid()).is_false()


func test_unordered_speeds_are_rejected() -> void:
	var species := _valid_species()
	species.walk_speed = species.run_speed + 1.0
	assert_array(Array(species.get_validation_errors())).contains(
		["speeds must satisfy walk_speed < trot_speed < run_speed"]
	)


func test_fast_turn_rate_above_slow_is_rejected() -> void:
	var species := _valid_species()
	species.turn_rate_fast = species.turn_rate_slow + 1.0
	assert_bool(species.is_valid()).is_false()


func test_slope_limit_must_be_below_vertical() -> void:
	var species := _valid_species()
	species.max_slope_degrees = 90.0
	assert_bool(species.is_valid()).is_false()
