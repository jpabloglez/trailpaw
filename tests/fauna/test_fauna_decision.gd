## Tests for [FaunaDecision] (pure) and [FaunaProfile] validation.
extends GdUnitTestSuite


func _profile() -> FaunaProfile:
	var p := FaunaProfile.new()
	p.flee_radius = 10.0
	p.flee_trigger_speed = 3.0
	p.startle_radius = 2.0
	p.safe_distance = 20.0
	return p


func _seen(distance: float, closing: float = 0.0) -> FaunaPerception:
	var p := FaunaPerception.new()
	p.player_distance = distance
	p.closing_speed = closing
	return p


func test_flees_from_a_fast_approach_within_the_flee_radius() -> void:
	var p := _profile()
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.GRAZE, false, _seen(8.0, 5.0), p, 0.1, 0.9))
		)
		. is_equal("Flee")
	)


func test_ignores_a_slow_or_far_player() -> void:
	var p := _profile()
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.GRAZE, false, _seen(8.0, 1.0), p, 0.1, 0.9))
		)
		. is_equal("Graze")
	)
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.GRAZE, false, _seen(15.0, 6.0), p, 0.1, 0.9))
		)
		. is_equal("Graze")
	)


func test_startled_when_very_close_even_slowly() -> void:
	var p := _profile()
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.REST, false, _seen(1.5, 0.0), p, 0.1, 0.9))
		)
		. is_equal("Flee")
	)


func test_keeps_fleeing_until_the_safe_distance() -> void:
	var p := _profile()
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.FLEE, false, _seen(15.0, -2.0), p, 0.1, 0.9))
		)
		. is_equal("Flee")
	)
	var calm := FaunaDecision.decide(FaunaDecision.FLEE, false, _seen(25.0, -2.0), p, 0.1, 0.9)
	assert_str(String(calm)).is_not_equal("Flee")


func test_approaches_only_if_curious_and_when_its_bout_is_done() -> void:
	var p := _profile()
	p.flee_radius = 0.0
	p.startle_radius = 0.0
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.WANDER, true, _seen(10.0), p, 0.1, 0.0))
		)
		. is_not_equal("Approach")
	)
	p.approach_radius = 15.0
	p.approach_stop_distance = 4.0
	p.approach_chance = 0.5
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.WANDER, true, _seen(10.0), p, 0.1, 0.2))
		)
		. is_equal("Approach")
	)
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.WANDER, true, _seen(10.0), p, 0.1, 0.8))
		)
		. is_not_equal("Approach")
	)
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.WANDER, false, _seen(10.0), p, 0.1, 0.2))
		)
		. is_equal("Wander")
	)
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.APPROACH, false, _seen(3.0), p, 0.1, 0.9))
		)
		. is_equal("Approach")
	)
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.APPROACH, true, _seen(3.0), p, 0.1, 0.9))
		)
		. is_not_equal("Approach")
	)


func test_follow_lasts_until_done_even_when_the_player_rushes() -> void:
	var p := _profile()
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.FOLLOW, false, _seen(1.0, 8.0), p, 0.1, 0.9))
		)
		. is_equal("Follow")
	)
	(
		assert_str(
			String(FaunaDecision.decide(FaunaDecision.FOLLOW, true, _seen(30.0), p, 0.1, 0.9))
		)
		. is_not_equal("Follow")
	)


func test_idle_choice_follows_the_weights() -> void:
	var p := _profile()
	p.idle_weights = Vector3(0.5, 0.3, 0.2)
	var counts := {FaunaDecision.WANDER: 0, FaunaDecision.GRAZE: 0, FaunaDecision.REST: 0}
	for i in 1000:
		counts[FaunaDecision.idle_choice(p, (i + 0.5) / 1000.0)] += 1
	assert_int(counts[FaunaDecision.WANDER]).is_equal(500)
	assert_int(counts[FaunaDecision.GRAZE]).is_equal(300)
	assert_int(counts[FaunaDecision.REST]).is_equal(200)


func test_profile_validation() -> void:
	assert_bool(_profile().is_valid()).is_true()
	var p := _profile()
	p.safe_distance = 5.0
	assert_bool(p.is_valid()).is_false()
	p = _profile()
	p.idle_weights = Vector3.ZERO
	assert_bool(p.is_valid()).is_false()
	(
		assert_bool((load("res://data/fauna/default_profile.tres") as FaunaProfile).is_valid())
		. is_true()
	)
