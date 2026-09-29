## Tests for footstep events derived from the animation's paw contacts.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"

var _animal: Animal
var _controller: AnimationController
var _steps: Array[StringName] = []


func before_test() -> void:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	_animal = auto_free(load(ANIMAL_SCENE).instantiate())
	_animal.position.y = 0.2
	add_child(_animal)
	_animal.get_node("%PlayerInput").set_physics_process(false)
	_controller = _animal.get_node("%AnimationController") as AnimationController
	_steps = []
	_controller.footstep.connect(func(paw: StringName) -> void: _steps.append(paw))


func _run_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _species() -> AnimalSpecies:
	return _animal.movement.species


func test_each_locomotion_clip_has_one_contact_per_paw() -> void:
	for logical: StringName in [&"walk", &"run"]:
		var clip: String = _species().animations[logical]
		var contacts := _controller.contacts_for(clip)
		assert_int(contacts.size()).is_equal(4)
		var paws := {}
		for contact: Array in contacts:
			paws[contact[1]] = true
			assert_float(contact[0]).is_greater_equal(0.0)
		assert_int(paws.size()).is_equal(4)


func test_no_footsteps_while_standing() -> void:
	await _run_for(1.0)
	_steps.clear()
	await _run_for(1.5)
	assert_array(_steps).is_empty()


func test_trotting_emits_steps_in_the_clip_order() -> void:
	await _run_for(0.5)
	_animal.movement.move_input = Vector2(0, -1)
	await _run_for(1.5)
	_steps.clear()
	await _run_for(2.0)
	assert_int(_steps.size()).is_greater(8)
	var order: Array = _controller.contacts_for(_species().animations[&"run"]).map(
		func(c: Array) -> StringName: return c[1]
	)
	# Consecutive steps follow the clip's contact order (cyclically).
	for i in range(1, _steps.size()):
		var expected: StringName = order[(order.find(_steps[i - 1]) + 1) % order.size()]
		assert_str(String(_steps[i])).is_equal(String(expected))


func test_running_steps_faster_than_trotting() -> void:
	await _run_for(0.5)
	_animal.movement.move_input = Vector2(0, -1)
	await _run_for(1.5)
	_steps.clear()
	await _run_for(2.0)
	var trot := _steps.size()
	_animal.movement.sprint = true
	await _run_for(1.5)
	_steps.clear()
	await _run_for(2.0)
	assert_int(_steps.size()).is_greater(trot)


func test_no_footsteps_while_swimming_or_airborne() -> void:
	await _run_for(0.5)
	_animal.movement.move_input = Vector2(0, -1)
	await _run_for(1.5)
	_animal.movement.swimming = true
	_steps.clear()
	await _run_for(1.0)
	assert_array(_steps).is_empty()
	_animal.movement.swimming = false
	_animal.movement.request_jump()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_steps.clear()
	await _run_for(0.3)  # mid-air
	assert_array(_steps).is_empty()
