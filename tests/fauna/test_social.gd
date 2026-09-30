## Tests for greeting, playing and following: the fox and a wild animal face to face.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const AGENT_SCENE: String = "res://scenes/fauna/fauna_agent.tscn"


func _floor() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)


## A copy of species [param id] that grazes for long (so it stays put) and follows briefly.
func _species(id: String) -> FaunaSpecies:
	var s := (load("res://data/fauna/%s.tres" % id) as FaunaSpecies).duplicate() as FaunaSpecies
	s.profile = s.profile.duplicate() as FaunaProfile
	s.profile.graze_time = Vector2(60, 60)
	s.profile.approach_radius = 0.0
	s.follow_seconds = 2.0
	return s


func _scene(id: String) -> Array:
	_floor()
	var fox: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	fox.position = Vector3(0, 0.05, 0)
	add_child(fox)
	fox.get_node("%PlayerInput").set_physics_process(false)
	var agent: FaunaAgent = auto_free(load(AGENT_SCENE).instantiate())
	agent.fauna = _species(id)
	agent.position = Vector3(0, 0.1, -1.5)
	add_child(agent)
	await get_tree().physics_frame
	agent.state_machine.transition_to(&"Graze")
	(agent.state_machine.get_state(&"Play") as FaunaPlayState).duration = 1.0
	for i in 20:
		await get_tree().physics_frame
	return [fox, agent]


func _interactor(fox: Animal) -> Interactor:
	return fox.get_node("%Interactor") as Interactor


func _state(agent: FaunaAgent) -> String:
	return String(agent.state_machine.current_state_name())


func _count(bus_signal: Signal) -> Array[int]:
	var counter: Array[int] = [0]
	bus_signal.connect(func(_id: StringName) -> void: counter[0] += 1)
	return counter


func test_greeting_a_calm_donkey() -> void:
	var setup: Array = await _scene("donkey")
	var fox: Animal = setup[0]
	var agent: FaunaAgent = setup[1]
	var interactor := _interactor(fox)
	interactor.probe()
	assert_str(interactor.current_target().definition.prompt).is_equal("Greet the donkey")
	var greeted := _count(EventBus.animal_greeted)
	interactor.request_interaction()
	await get_tree().create_timer(0.3).timeout
	assert_str(_state(agent)).is_equal("Social")  # it stops and sniffs back
	await get_tree().create_timer(2.2).timeout
	assert_int(greeted[0]).is_equal(1)
	interactor.probe()
	assert_object(interactor.current_target()).is_null()  # calm: no play, greeting cools down
	assert_str(agent.social_definition().prompt).is_equal("Greet the donkey")


func test_a_friendly_shiba_plays_and_then_follows_for_a_while() -> void:
	var setup: Array = await _scene("shiba_inu")
	var fox: Animal = setup[0]
	var agent: FaunaAgent = setup[1]
	var interactor := _interactor(fox)
	var played := _count(EventBus.animal_played)
	interactor.probe()
	interactor.request_interaction()
	await get_tree().create_timer(2.4).timeout
	interactor.probe()
	assert_str(interactor.current_target().definition.prompt).is_equal("Play with the shiba inu")
	interactor.request_interaction()
	await get_tree().create_timer(1.8).timeout
	assert_int(played[0]).is_equal(1)
	assert_str(_state(agent)).is_equal("Play")
	await get_tree().create_timer(1.2).timeout
	assert_str(_state(agent)).is_equal("Follow")
	await get_tree().create_timer(2.5).timeout
	assert_str(_state(agent)).is_not_equal("Follow")  # the follow ends


func test_a_curious_alpaca_plays_but_does_not_follow() -> void:
	var setup: Array = await _scene("alpaca")
	var fox: Animal = setup[0]
	var agent: FaunaAgent = setup[1]
	var interactor := _interactor(fox)
	interactor.probe()
	interactor.request_interaction()
	await get_tree().create_timer(2.4).timeout
	interactor.probe()
	assert_str(interactor.current_target().definition.prompt).is_equal("Play with the alpaca")
	interactor.request_interaction()
	await get_tree().create_timer(3.0).timeout
	assert_str(_state(agent)).is_not_equal("Follow")


func test_a_fleeing_deer_cannot_be_greeted() -> void:
	var setup: Array = await _scene("deer")
	var fox: Animal = setup[0]
	var agent: FaunaAgent = setup[1]
	agent.state_machine.transition_to(&"Flee")
	await get_tree().physics_frame
	var interactor := _interactor(fox)
	interactor.probe()
	assert_object(interactor.current_target()).is_null()


func test_a_shy_deer_can_be_greeted_after_a_calm_approach() -> void:
	var setup: Array = await _scene("deer")
	var fox: Animal = setup[0]
	var agent: FaunaAgent = setup[1]
	var greeted := _count(EventBus.animal_greeted)
	var interactor := _interactor(fox)
	interactor.probe()
	assert_str(interactor.current_target().definition.prompt).is_equal("Greet the deer")
	interactor.request_interaction()
	await get_tree().create_timer(2.4).timeout
	assert_int(greeted[0]).is_equal(1)
	assert_str(_state(agent)).is_not_equal("Flee")
