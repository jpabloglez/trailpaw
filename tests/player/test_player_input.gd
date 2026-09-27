## Tests that [PlayerInput] maps InputMap actions to [MovementComponent] intent.
extends GdUnitTestSuite

var _movement: MovementComponent
var _input: PlayerInput


func before_test() -> void:
	var body: CharacterBody3D = auto_free(CharacterBody3D.new())
	_movement = MovementComponent.new()
	_movement.species = load("res://data/species/placeholder.tres")
	_input = PlayerInput.new()
	_input.movement = _movement
	body.add_child(_movement)
	body.add_child(_input)
	add_child(body)


func after_test() -> void:
	for action: StringName in [&"move_forward", &"move_right", &"sprint", &"jump"]:
		Input.action_release(action)


func test_move_and_sprint_actions_become_intent() -> void:
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	_input._physics_process(0.016)
	assert_vector(_movement.move_input).is_equal_approx(Vector2(0, -1), Vector2.ONE * 1e-4)
	assert_bool(_movement.sprint).is_true()


func test_released_actions_clear_intent() -> void:
	Input.action_press(&"move_right")
	_input._physics_process(0.016)
	Input.action_release(&"move_right")
	_input._physics_process(0.016)
	assert_vector(_movement.move_input).is_equal(Vector2.ZERO)
	assert_bool(_movement.sprint).is_false()


func test_input_runs_before_other_physics_callbacks() -> void:
	assert_int(_input.process_physics_priority).is_less(0)
