## Tests for the four temperaments: each reacts to the player as specified (through
## [FaunaDecision]), and [FaunaSpecies] data validation and traits.
extends GdUnitTestSuite

const DIR: String = "res://data/fauna/temperaments/"
const FOX: String = "res://data/species/fox.tres"


func _profile(temperament: String) -> FaunaProfile:
	return load(DIR + temperament + ".tres") as FaunaProfile


func _seen(distance: float, closing: float) -> FaunaPerception:
	var p := FaunaPerception.new()
	p.player_distance = distance
	p.closing_speed = closing
	return p


func _reaction(
	temperament: String, distance: float, closing: float, approach_roll := 0.0
) -> String:
	var next := FaunaDecision.decide(
		FaunaDecision.WANDER,
		true,
		_seen(distance, closing),
		_profile(temperament),
		0.1,
		approach_roll
	)
	return String(next)


func test_every_temperament_profile_is_valid() -> void:
	for t: String in ["shy", "curious", "friendly", "calm"]:
		assert_array(Array(_profile(t).get_validation_errors())).is_empty()


func test_a_player_running_in_from_ten_metres_only_scares_the_shy() -> void:
	assert_str(_reaction("shy", 10.0, 5.0, 0.99)).is_equal("Flee")
	assert_str(_reaction("curious", 10.0, 5.0, 0.99)).is_not_equal("Flee")
	assert_str(_reaction("friendly", 10.0, 5.0, 0.99)).is_not_equal("Flee")
	assert_str(_reaction("calm", 10.0, 5.0, 0.99)).is_not_equal("Flee")


func test_walking_up_slowly_startles_the_shy_but_not_the_calm() -> void:
	assert_str(_reaction("shy", 4.0, 1.0, 0.99)).is_equal("Flee")
	assert_str(_reaction("calm", 4.0, 1.0, 0.99)).is_not_equal("Flee")
	assert_str(_reaction("calm", 1.0, 0.5, 0.99)).is_equal("Flee")  # only right on top of it


func test_only_curious_and_friendly_animals_come_to_look() -> void:
	assert_str(_reaction("curious", 12.0, 0.0)).is_equal("Approach")
	assert_str(_reaction("friendly", 12.0, 0.0)).is_equal("Approach")
	assert_str(_reaction("shy", 20.0, 0.0)).is_not_equal("Approach")
	assert_str(_reaction("calm", 12.0, 0.0)).is_not_equal("Approach")


func test_friendly_animals_come_closer_than_curious_ones() -> void:
	assert_float(_profile("friendly").approach_stop_distance).is_less(
		_profile("curious").approach_stop_distance
	)


func test_calm_animals_graze_most() -> void:
	var calm := _profile("calm").idle_weights
	assert_float(calm.y / (calm.x + calm.y + calm.z)).is_greater(0.5)


func test_traits_by_temperament() -> void:
	var s := FaunaSpecies.new()
	var expected := {
		FaunaSpecies.Temperament.SHY: [false, false],
		FaunaSpecies.Temperament.CURIOUS: [true, false],
		FaunaSpecies.Temperament.FRIENDLY: [true, true],
		FaunaSpecies.Temperament.CALM: [false, false],
	}
	for t: int in expected:
		s.temperament = t
		assert_bool(s.can_play()).is_equal(expected[t][0])
		assert_bool(s.follows_after_play()).is_equal(expected[t][1])
		assert_bool(s.can_be_greeted()).is_true()


func test_species_validation() -> void:
	var s := FaunaSpecies.new()
	assert_bool(s.is_valid()).is_false()
	s.id = &"test"
	s.display_name = "Test"
	s.animal = load(FOX)
	s.profile = _profile("shy")
	assert_array(Array(s.get_validation_errors())).is_empty()
	s.herd_size = Vector2i(3, 2)
	assert_bool(s.is_valid()).is_false()


func test_an_agent_takes_its_profile_and_radius_from_the_species() -> void:
	var s := FaunaSpecies.new()
	s.id = &"test"
	s.display_name = "Test"
	s.animal = load(FOX)
	s.profile = _profile("friendly")
	s.wander_radius = 33.0
	var agent: FaunaAgent = auto_free(load("res://scenes/fauna/fauna_agent.tscn").instantiate())
	agent.fauna = s
	add_child(agent)
	assert_object(agent.brain.profile).is_same(s.profile)
	assert_object(agent.movement.species).is_same(s.animal)
	assert_float((agent.state_machine.get_state(&"Wander") as FaunaWanderState).radius).is_equal(
		33.0
	)
