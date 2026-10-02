## Tests for the four temperaments: each reacts to the player as specified (through
## [FaunaDecision]), and [FaunaSpecies] data validation and traits.
extends GdUnitTestSuite

const DIR: String = "res://data/fauna/temperaments/"
const FOX: String = "res://data/species/fox.tres"
const BIOMES: Array[String] = ["meadow", "forest", "hills", "river_valley"]


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


func _fox() -> AnimalSpecies:
	return load(FOX) as AnimalSpecies


func test_a_player_running_in_from_seven_metres_only_scares_the_shy() -> void:
	var run := _fox().run_speed
	assert_str(_reaction("shy", 7.0, run, 0.99)).is_equal("Flee")
	assert_str(_reaction("curious", 7.0, run, 0.99)).is_not_equal("Flee")
	assert_str(_reaction("friendly", 7.0, run, 0.99)).is_not_equal("Flee")
	assert_str(_reaction("calm", 7.0, run, 0.99)).is_not_equal("Flee")


func test_a_slow_approach_lets_you_close_to_the_shy_but_rushing_in_does_not() -> void:
	# User decision: shy animals flee "if you approach fast"; walking up slowly is fine.
	assert_str(_reaction("shy", 4.0, 1.0, 0.99)).is_not_equal("Flee")
	assert_str(_reaction("shy", 4.0, _fox().run_speed, 0.99)).is_equal("Flee")
	assert_str(_reaction("shy", 0.8, 0.0, 0.99)).is_equal("Flee")  # bumped into
	assert_str(_reaction("calm", 4.0, _fox().run_speed, 0.99)).is_not_equal("Flee")
	assert_str(_reaction("calm", 1.0, 0.5, 0.99)).is_equal("Flee")  # only right on top of it


func test_trotting_up_scares_nobody() -> void:
	# Phase 8 playtest: animals felt skittish. Only running (not trotting) makes the shy flee.
	var trot := _fox().trot_speed
	for t: String in ["shy", "curious", "friendly", "calm"]:
		for distance: float in [2.0, 5.0, 10.0]:
			var reaction := _reaction(t, distance, trot, 0.99)
			(
				assert_str(reaction)
				. override_failure_message("%s at %s m" % [t, distance])
				. is_not_equal("Flee")
			)


func test_herds_are_big_enough_to_be_seen_together() -> void:
	assert_int((load("res://data/fauna/deer.tres") as FaunaSpecies).herd_size.x).is_greater_equal(3)
	assert_int((load("res://data/fauna/horse.tres") as FaunaSpecies).herd_size.x).is_greater_equal(
		2
	)
	assert_int((load("res://data/fauna/alpaca.tres") as FaunaSpecies).herd_size.x).is_greater_equal(
		2
	)


func test_every_biome_hosts_enough_animals() -> void:
	# Expected animals per chunk: chance × weighted mean herd size (Phase 8 playtest: sparse).
	for id in BIOMES:
		var biome := load("res://data/biomes/%s.tres" % id) as BiomeDefinition
		var total_weight := 0.0
		var herd := 0.0
		for entry in biome.fauna:
			total_weight += entry.weight
			herd += entry.weight * (entry.species.herd_size.x + entry.species.herd_size.y) * 0.5
		var density := biome.fauna_chance * herd / total_weight
		assert_float(density).override_failure_message(id).is_greater_equal(0.4)


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
