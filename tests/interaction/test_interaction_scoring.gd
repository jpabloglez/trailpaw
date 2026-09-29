## Tests for [InteractionScoring] and [InteractionDefinition] validation.
extends GdUnitTestSuite

const FORWARD := Vector3(0, 0, -1)


func _score(target: Vector3) -> float:
	return InteractionScoring.score(Vector3.ZERO, FORWARD, target, 2.0, 80.0, 0.6)


func test_closer_scores_higher() -> void:
	assert_float(_score(Vector3(0, 0, -0.5))).is_greater(_score(Vector3(0, 0, -1.5)))


func test_in_front_scores_higher_than_to_the_side() -> void:
	assert_float(_score(Vector3(0, 0, -1))).is_greater(_score(Vector3(0.9, 0, -0.45)))


func test_out_of_reach_or_behind_is_rejected() -> void:
	assert_float(_score(Vector3(0, 0, -2.5))).is_equal(-1.0)
	assert_float(_score(Vector3(0, 0, 1))).is_equal(-1.0)


func test_height_does_not_matter() -> void:
	assert_float(_score(Vector3(0, 1.5, -1))).is_equal_approx(_score(Vector3(0, 0, -1)), 1e-5)


func test_target_at_the_origin_scores_positive() -> void:
	assert_float(_score(Vector3.ZERO)).is_greater(0.0)


func test_definition_validation() -> void:
	var definition := InteractionDefinition.new()
	assert_bool(definition.is_valid()).is_false()
	definition.id = &"test"
	definition.prompt = "Test"
	definition.animation = &"eat"
	definition.food_kind = &"berries"
	definition.duration = 1.0
	assert_array(Array(definition.get_validation_errors())).is_empty()
	definition.food_kind = &""
	assert_bool(definition.is_valid()).is_false()  # EAT needs a food kind
	definition.type = InteractionDefinition.Type.DRINK
	definition.mode = InteractionDefinition.Mode.HOLD
	definition.duration = 0.0
	assert_bool(definition.is_valid()).is_true()
