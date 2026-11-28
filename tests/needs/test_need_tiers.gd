## Tests for [enum NeedsModel.Tier]: normal → low (critical) → empty at 0, with hysteresis on
## the way back, one [signal NeedsModel.tier_changed] per change, and the feeling-well check.
extends GdUnitTestSuite

const IDS: Array[StringName] = [&"hunger", &"thirst", &"temperature", &"energy"]
const NORMAL := NeedsModel.Tier.NORMAL
const LOW := NeedsModel.Tier.LOW
const EMPTY := NeedsModel.Tier.EMPTY

var _changes: Array = []


func _model() -> NeedsModel:
	var definitions: Array[NeedDefinition] = []
	for id in IDS:
		definitions.append(load("res://data/needs/%s.tres" % id))
	var model := NeedsModel.new(definitions, load("res://data/needs/need_modifiers.tres"))
	_changes = []
	model.tier_changed.connect(func(id: StringName, tier: int) -> void: _changes.append([id, tier]))
	return model


func test_needs_start_normal() -> void:
	var model := _model()
	for id in IDS:
		assert_int(model.tier(id)).is_equal(NORMAL)


func test_tiers_follow_the_value_down() -> void:
	var model := _model()
	model.set_value(&"thirst", 30.0)
	assert_int(model.tier(&"thirst")).is_equal(NORMAL)
	model.set_value(&"thirst", 25.0)
	assert_int(model.tier(&"thirst")).is_equal(LOW)
	model.set_value(&"thirst", 0.5)
	assert_int(model.tier(&"thirst")).is_equal(LOW)
	model.set_value(&"thirst", -5.0)
	assert_int(model.tier(&"thirst")).is_equal(EMPTY)
	assert_array(_changes).is_equal([[&"thirst", LOW], [&"thirst", EMPTY]])


func test_empty_holds_until_above_its_margin() -> void:
	var model := _model()
	model.set_value(&"energy", 0.0)
	model.set_value(&"energy", 8.0)  # the margin itself: still empty
	assert_int(model.tier(&"energy")).is_equal(EMPTY)
	model.set_value(&"energy", 8.5)
	assert_int(model.tier(&"energy")).is_equal(LOW)
	model.set_value(&"energy", 4.0)  # dipping again without reaching 0 stays low
	assert_int(model.tier(&"energy")).is_equal(LOW)


func test_a_big_refill_jumps_straight_back_to_normal() -> void:
	var model := _model()
	model.set_value(&"hunger", 0.0)
	_changes.clear()
	model.refill_all()
	assert_int(model.tier(&"hunger")).is_equal(NORMAL)
	assert_array(_changes).is_equal([[&"hunger", NORMAL]])


func test_falling_from_full_to_empty_is_one_change() -> void:
	var model := _model()
	model.set_value(&"temperature", 0.0)
	assert_array(_changes).is_equal([[&"temperature", EMPTY]])
	assert_bool(model.is_critical(&"temperature")).is_true()


func test_ticking_down_reaches_empty() -> void:
	var model := _model()
	model.set_value(&"thirst", 2.0)
	for i in 120:  # 30 s of trotting: −4.7
		model.tick(0.25, NeedsModel.Activity.TROT, 0.0)
	assert_int(model.tier(&"thirst")).is_equal(EMPTY)


func test_all_at_least() -> void:
	var model := _model()
	assert_bool(model.all_at_least(0.7)).is_true()
	model.set_value(&"energy", 69.0)
	assert_bool(model.all_at_least(0.7)).is_false()
	assert_bool(model.all_at_least(0.6)).is_true()
