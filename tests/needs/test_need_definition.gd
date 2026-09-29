## Tests for [NeedDefinition] validation and the four need resources in data/needs/.
extends GdUnitTestSuite

## Need id → minutes from full to critical while trotting (the chosen "moderate" pacing).
const PACING: Dictionary = {
	&"thirst": 8.0,
	&"hunger": 12.0,
	&"energy": 15.0,
	&"temperature": 10.0,
}


func _need(id: StringName) -> NeedDefinition:
	return load("res://data/needs/%s.tres" % id) as NeedDefinition


func test_every_need_loads_and_is_valid() -> void:
	for id: StringName in PACING:
		var need := _need(id)
		assert_object(need).is_not_null()
		assert_array(Array(need.get_validation_errors())).is_empty()


func test_ids_match_their_files_and_are_unique() -> void:
	var seen := {}
	for id: StringName in PACING:
		assert_str(String(_need(id).id)).is_equal(String(id))
		seen[_need(id).id] = true
	assert_int(seen.size()).is_equal(PACING.size())


func test_time_to_critical_follows_the_chosen_pacing() -> void:
	for id: StringName in PACING:
		var minutes: float = PACING[id]
		assert_float(_need(id).minutes_to_critical()).is_equal_approx(minutes, minutes * 0.05)


func test_thirst_comes_before_hunger_before_energy() -> void:
	assert_float(_need(&"thirst").minutes_to_critical()).is_less(
		_need(&"hunger").minutes_to_critical()
	)
	assert_float(_need(&"hunger").minutes_to_critical()).is_less(
		_need(&"energy").minutes_to_critical()
	)


func test_only_energy_makes_the_animal_look_tired() -> void:
	for id: StringName in PACING:
		assert_bool(_need(id).tired_when_critical).is_equal(id == &"energy")


func test_consequences_are_soft() -> void:
	# ADR-003: critical needs slow the animal a little, never stop it.
	for id: StringName in PACING:
		assert_float(_need(id).critical_speed_factor).is_between(0.7, 1.0)


func test_unconfigured_need_is_invalid() -> void:
	assert_bool(NeedDefinition.new().is_valid()).is_false()
	assert_float(NeedDefinition.new().minutes_to_critical()).is_equal(INF)


func test_thresholds_must_leave_room_for_recovery() -> void:
	var need := _need(&"thirst").duplicate() as NeedDefinition
	need.critical_threshold = 95.0
	assert_bool(need.is_valid()).is_false()
	need = _need(&"thirst").duplicate() as NeedDefinition
	need.recover_margin = 0.0
	assert_bool(need.is_valid()).is_false()


func test_speed_factor_must_be_a_slowdown() -> void:
	var need := _need(&"energy").duplicate() as NeedDefinition
	need.critical_speed_factor = 0.0
	assert_bool(need.is_valid()).is_false()
