## Integration test: the Animal scene on a real physics floor.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const MAX_SETTLE_FRAMES: int = 180

var _animal: Animal
var _states: Array[StringName] = []


func before_test() -> void:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)  # top face at y = 0
	floor_body.add_child(shape)
	add_child(floor_body)
	_animal = auto_free(load(ANIMAL_SCENE).instantiate())
	_animal.position = Vector3(0.0, 0.2, 0.0)
	add_child(_animal)
	# Tests drive the movement intent directly; stop PlayerInput from overwriting it.
	_animal.get_node("%PlayerInput").set_physics_process(false)
	_states = []
	_animal.state_machine.state_changed.connect(
		func(_from: StringName, to: StringName) -> void: _states.append(to)
	)


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _settle() -> void:
	for i in MAX_SETTLE_FRAMES:
		await get_tree().physics_frame
		if _animal.is_on_floor() and _animal.state_machine.current_state_name() == &"Idle":
			return


func test_scene_has_components_and_starts_idle_on_floor() -> void:
	await _settle()
	assert_object(_animal.movement).is_not_null()
	assert_bool(_animal.is_in_group(Animal.PLAYER_GROUP)).is_true()
	assert_bool(_animal.is_on_floor()).is_true()
	assert_str(String(_animal.state_machine.current_state_name())).is_equal("Idle")


func test_forward_input_moves_along_forward_within_speed_limit() -> void:
	await _settle()
	var start := _animal.global_position
	var max_speed := 0.0
	_animal.movement.move_input = Vector2(0.0, -1.0)
	_animal.movement.sprint = true
	for i in 90:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, _animal.movement.horizontal_speed())
	assert_str(String(_animal.state_machine.current_state_name())).is_equal("Locomotion")
	# No camera in the test tree: forward is the body's initial -Z.
	assert_float(_animal.global_position.z).is_less(start.z - 1.0)
	assert_float(max_speed).is_less_equal(_animal.movement.species.run_speed + 1e-3)


func test_releasing_input_returns_to_idle() -> void:
	await _settle()
	_animal.movement.move_input = Vector2(0.0, -1.0)
	await _physics_frames(30)
	_animal.movement.move_input = Vector2.ZERO
	await _physics_frames(60)
	assert_str(String(_animal.state_machine.current_state_name())).is_equal("Idle")


func test_jump_cycles_through_jump_and_fall_back_to_idle() -> void:
	await _settle()
	_states.clear()
	_animal.movement.request_jump()
	await _physics_frames(120)
	assert_array(_states).contains_exactly([&"Jump", &"Fall", &"Idle"])
	assert_bool(_animal.is_on_floor()).is_true()
