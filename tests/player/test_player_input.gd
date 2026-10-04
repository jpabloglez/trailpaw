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
	for action: StringName in [&"move_forward", &"move_right", &"sprint", &"jump", &"rest"]:
		Input.action_release(action)
	Settings.set_sprint_toggle(false)
	Settings.set_rest_toggle(false)


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


func test_toggle_step() -> void:
	assert_bool(PlayerInput.toggle_step(false, true, false)).is_true()  # press: on
	assert_bool(PlayerInput.toggle_step(true, false, false)).is_true()  # stays on
	assert_bool(PlayerInput.toggle_step(true, true, false)).is_false()  # press again: off
	assert_bool(PlayerInput.toggle_step(true, false, true)).is_false()  # cancelled: off


func test_toggle_sprint_runs_until_pressed_again_or_stopped() -> void:
	Settings.set_sprint_toggle(true)
	_movement.move_input = Vector2(0, -1)
	assert_bool(_input.sprint_intent(true, true)).is_true()  # press: run
	assert_bool(_input.sprint_intent(false, false)).is_true()  # key up: still running
	assert_bool(_input.sprint_intent(true, true)).is_false()  # press again: walk
	assert_bool(_input.sprint_intent(true, true)).is_true()
	_movement.move_input = Vector2.ZERO
	assert_bool(_input.sprint_intent(false, false)).is_false()  # stopping cancels it


func test_hold_sprint_is_unchanged() -> void:
	_movement.move_input = Vector2(0, -1)
	assert_bool(_input.sprint_intent(true, true)).is_true()
	assert_bool(_input.sprint_intent(true, false)).is_true()
	assert_bool(_input.sprint_intent(false, false)).is_false()  # released: walking again


func test_toggle_rest_lies_down_until_pressed_again_or_moving() -> void:
	Settings.set_rest_toggle(true)
	assert_bool(_input.rest_intent(true, true)).is_true()  # press: lie down
	assert_bool(_input.rest_intent(false, false)).is_true()  # no need to hold it
	assert_bool(_input.rest_intent(true, true)).is_false()  # press again: up
	assert_bool(_input.rest_intent(true, true)).is_true()
	_movement.move_input = Vector2(1, 0)
	assert_bool(_input.rest_intent(false, false)).is_false()  # moving gets up


func test_the_rest_intent_reaches_the_rester() -> void:
	var rester: Rester = auto_free(Rester.new())
	_input.rester = rester
	Input.action_press(&"rest")
	_input._physics_process(0.016)
	assert_bool(rester.rest_held).is_true()
