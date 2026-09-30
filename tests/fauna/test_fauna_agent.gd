## Scene tests for [FaunaAgent]: world-relative intent, grounding, animation and floating origin.
extends GdUnitTestSuite

const AGENT_SCENE: String = "res://scenes/fauna/fauna_agent.tscn"
const FOX: String = "res://data/species/fox.tres"  # stand-in until the fauna species arrive


func _floor() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)


func _agent(at: Vector3 = Vector3(0, 0.1, 0), agent_seed: int = 7) -> FaunaAgent:
	var agent: FaunaAgent = auto_free(load(AGENT_SCENE).instantiate())
	agent.species = load(FOX)
	agent.decision_seed = agent_seed
	agent.position = at
	add_child(agent)
	agent.brain.set_physics_process(false)  # these tests drive Wander by hand
	return agent


func _wander(agent: FaunaAgent) -> FaunaWanderState:
	return agent.state_machine.get_state(&"Wander") as FaunaWanderState


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_the_agent_gets_its_species_model_and_lives_on_the_fauna_layer() -> void:
	_floor()
	var agent := _agent()
	await _frames(2)
	assert_object(agent.movement.species).is_same(load(FOX))
	assert_int(agent.model_root.get_child_count()).is_greater(0)
	assert_int(agent.collision_layer).is_equal(FaunaAgent.LAYER)
	assert_int(agent.collision_mask).is_equal(1)
	assert_bool(agent.is_in_group(FaunaAgent.GROUP)).is_true()
	assert_bool(agent.movement.camera_relative).is_false()


func test_walks_to_its_target_in_world_space_whatever_the_camera() -> void:
	_floor()
	var camera: Camera3D = auto_free(Camera3D.new())
	camera.rotation.y = 1.3  # a camera looking elsewhere must not matter
	add_child(camera)
	camera.make_current()
	var agent := _agent()
	await _frames(5)
	_wander(agent).set_target(Vector3(8, 0, 0))
	await _frames(480)  # turn in an arc, then walk ~7 m
	assert_float(agent.global_position.x).is_greater(6.5)
	assert_float(absf(agent.global_position.z)).is_less(1.0)
	assert_bool(agent.is_on_floor()).is_true()


func test_wanders_around_home_with_pauses_and_deterministically() -> void:
	_floor()
	var a := _agent(Vector3(0, 0.1, 0), 11)
	var b := _agent(Vector3(40, 0.1, 0), 11)
	await _frames(2)
	assert_float(_wander(a).target().x - a.home.x).is_equal_approx(
		_wander(b).target().x - b.home.x, 1e-4
	)
	var targets := {}
	for i in 5:
		_wander(a).pick_target()
		targets[_wander(a).target()] = true
		assert_float(a.home.distance_to(_wander(a).target())).is_less_equal(_wander(a).radius)
	assert_int(targets.size()).is_equal(5)


func test_animation_follows_its_walking() -> void:
	_floor()
	var agent := _agent()
	await _frames(5)
	_wander(agent).set_target(Vector3(0, 0, -20))
	await _frames(120)
	var controller := agent.get_node("%AnimationController") as AnimationController
	assert_str(String(controller.current_state())).is_equal("locomotion")
	var blend: float = controller.tree().get("parameters/locomotion/gait/blend_position")
	assert_float(blend).is_greater(0.3)
	assert_float(agent.movement.horizontal_speed()).is_less_equal(agent.species.walk_speed + 0.5)


func test_follows_floating_origin_rebases() -> void:
	_floor()
	var agent := _agent(Vector3(5, 0.1, 5))
	await _frames(2)
	var home := agent.home
	var position := agent.global_position
	var offset := Vector3(64, 0, 0)
	for node in get_tree().get_nodes_in_group(FloatingOrigin.SHIFTABLE_GROUP):
		if node == agent:
			agent.global_position -= offset
	EventBus.origin_shifted.emit(offset)
	assert_float(agent.global_position.x).is_equal_approx(position.x - 64.0, 1e-3)
	assert_float(agent.home.x).is_equal_approx(home.x - 64.0, 1e-3)
