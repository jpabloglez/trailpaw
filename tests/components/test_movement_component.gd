## Tests for [MovementComponent] setup, intent handling and jump requests.
extends GdUnitTestSuite

const SPECIES_PATH: String = "res://data/species/placeholder.tres"


func _make_component() -> MovementComponent:
	var body: CharacterBody3D = auto_free(CharacterBody3D.new())
	var movement := MovementComponent.new()
	movement.species = load(SPECIES_PATH)
	body.add_child(movement)
	add_child(body)
	return movement


func test_applies_species_slope_limit_to_body() -> void:
	var movement := _make_component()
	var body := movement.get_parent() as CharacterBody3D
	assert_float(body.floor_max_angle).is_equal_approx(
		deg_to_rad(movement.species.max_slope_degrees), 1e-5
	)


func test_move_input_deadzone() -> void:
	var movement := _make_component()
	movement.move_input = Vector2(0.05, 0.0)
	assert_bool(movement.has_move_input()).is_false()
	movement.move_input = Vector2(0.0, -1.0)
	assert_bool(movement.has_move_input()).is_true()


func test_jump_request_is_consumed_once() -> void:
	var movement := _make_component()
	assert_bool(movement.consume_jump_request()).is_false()
	movement.request_jump()
	assert_bool(movement.consume_jump_request()).is_true()
	assert_bool(movement.consume_jump_request()).is_false()


func test_stale_jump_request_expires() -> void:
	var movement := _make_component()
	movement.request_jump()
	for i in MovementComponent.JUMP_REQUEST_FRAMES + 2:
		await get_tree().physics_frame
	assert_bool(movement.consume_jump_request()).is_false()


func test_ground_movement_accelerates_along_heading() -> void:
	var movement := _make_component()
	var body := movement.get_parent() as CharacterBody3D
	movement.move_input = Vector2(0.0, -1.0)
	movement.apply_ground_movement(0.1)
	assert_float(movement.horizontal_speed()).is_greater(0.0)
	# No camera in the test viewport: forward is the body's own -Z.
	assert_float(body.velocity.z).is_less(0.0)
	assert_float(absf(body.velocity.x)).is_less(1e-4)
