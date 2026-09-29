## Transition tests for the player states, using a scripted [MovementComponent] double.
extends GdUnitTestSuite


## Movement double: queries return scripted values; actions are recorded, not simulated.
class FakeMovement:
	extends MovementComponent

	var grounded: bool = true
	var moving: bool = false
	var speed: float = 0.0
	var rising_speed: float = 0.0
	var jump_requested: bool = false
	var deep: bool = false
	var shallow_bottom: bool = false
	var calls: Array[String] = []

	func _ready() -> void:
		pass

	func is_grounded() -> bool:
		return grounded

	func has_move_input() -> bool:
		return moving

	func horizontal_speed() -> float:
		return speed

	func vertical_speed() -> float:
		return rising_speed

	func consume_jump_request() -> bool:
		var requested := jump_requested
		jump_requested = false
		return requested

	func should_start_swimming() -> bool:
		return deep

	func should_stop_swimming() -> bool:
		return shallow_bottom

	func apply_swim_movement(_delta: float) -> void:
		calls.append("swim")

	func apply_ground_movement(_delta: float) -> void:
		calls.append("ground")

	func apply_air_movement(_delta: float) -> void:
		calls.append("air")

	func apply_gravity(_delta: float) -> void:
		calls.append("gravity")

	func perform_jump() -> void:
		calls.append("jump")

	func move() -> void:
		calls.append("move")


var _movement: FakeMovement
var _machine: StateMachine


func before_test() -> void:
	var actor: Node = auto_free(Node.new())
	_movement = FakeMovement.new()
	_machine = StateMachine.new()
	var states: Array[PlayerState] = [
		PlayerIdleState.new(),
		PlayerLocomotionState.new(),
		PlayerJumpState.new(),
		PlayerFallState.new(),
		PlayerSwimState.new(),
	]
	var names: Array[StringName] = [
		PlayerState.IDLE,
		PlayerState.LOCOMOTION,
		PlayerState.JUMP,
		PlayerState.FALL,
		PlayerState.SWIM
	]
	for i in states.size():
		states[i].name = names[i]
		states[i].movement = _movement
		_machine.add_child(states[i])
	actor.add_child(_movement)
	actor.add_child(_machine)
	add_child(actor)
	_machine.set_physics_process(false)  # ticks are driven manually below


func _tick() -> void:
	_machine.current_state.physics_update(1.0 / 60.0)


func _state() -> String:
	return String(_machine.current_state_name())


func test_starts_idle() -> void:
	assert_str(_state()).is_equal("Idle")


func test_idle_to_locomotion_on_input() -> void:
	_movement.moving = true
	_tick()
	assert_str(_state()).is_equal("Locomotion")


func test_locomotion_to_idle_once_stopped() -> void:
	_machine.transition_to(PlayerState.LOCOMOTION)
	_movement.moving = false
	_movement.speed = 1.0
	_tick()
	assert_str(_state()).is_equal("Locomotion")  # still decelerating
	_movement.speed = 0.0
	_tick()
	assert_str(_state()).is_equal("Idle")


func test_jump_from_idle_performs_jump_then_falls_at_apex() -> void:
	_movement.jump_requested = true
	_tick()
	assert_str(_state()).is_equal("Jump")
	assert_array(_movement.calls).contains(["jump"])
	_movement.grounded = false
	_movement.rising_speed = 3.0
	_tick()
	assert_str(_state()).is_equal("Jump")
	_movement.rising_speed = 0.0
	_tick()
	assert_str(_state()).is_equal("Fall")


func test_jump_from_locomotion() -> void:
	_machine.transition_to(PlayerState.LOCOMOTION)
	_movement.jump_requested = true
	_tick()
	assert_str(_state()).is_equal("Jump")


func test_no_jump_while_airborne() -> void:
	_machine.transition_to(PlayerState.FALL)
	_movement.grounded = false
	_movement.jump_requested = true
	_tick()
	assert_str(_state()).is_equal("Fall")
	assert_array(_movement.calls).not_contains(["jump"])


func test_walking_off_a_ledge_falls() -> void:
	_machine.transition_to(PlayerState.LOCOMOTION)
	_movement.moving = true
	_movement.grounded = false
	_tick()
	assert_str(_state()).is_equal("Fall")


func test_landing_without_input_goes_idle() -> void:
	_machine.transition_to(PlayerState.FALL)
	_movement.grounded = true
	_tick()
	assert_str(_state()).is_equal("Idle")


func test_landing_while_moving_keeps_locomotion() -> void:
	_machine.transition_to(PlayerState.FALL)
	_movement.grounded = true
	_movement.moving = true
	_tick()
	assert_str(_state()).is_equal("Locomotion")


func test_air_states_use_air_control() -> void:
	_machine.transition_to(PlayerState.FALL)
	_movement.grounded = false
	_movement.calls.clear()
	_tick()
	assert_array(_movement.calls).contains_exactly(["air", "gravity", "move"])


# --- swimming -------------------------------------------------------------------------


func test_deep_water_starts_swimming_from_ground_and_air() -> void:
	_movement.deep = true
	_tick()
	assert_str(_state()).is_equal("Swim")
	assert_bool(_movement.swimming).is_true()
	_machine.transition_to(PlayerState.FALL)
	_movement.grounded = false
	_tick()
	assert_str(_state()).is_equal("Swim")


func test_no_jumping_while_swimming() -> void:
	_movement.deep = true
	_tick()
	_movement.jump_requested = true
	_tick()
	assert_str(_state()).is_equal("Swim")
	assert_array(_movement.calls).not_contains(["jump"])
	assert_bool(_movement.jump_requested).is_false()  # request consumed, not buffered


func test_reaching_the_shore_ends_swimming() -> void:
	_movement.deep = true
	_tick()
	_movement.deep = false
	_movement.shallow_bottom = true
	_movement.moving = true
	_tick()
	assert_str(_state()).is_equal("Locomotion")
	assert_bool(_movement.swimming).is_false()
