## Tests for [NeedsModel]: decay rates, clamping, activity/biome/water modifiers and critical
## signals with hysteresis.
extends GdUnitTestSuite

const IDS: Array[StringName] = [&"hunger", &"thirst", &"temperature", &"energy"]
const TROT := NeedsModel.Activity.TROT
const IDLE := NeedsModel.Activity.IDLE
const RUN := NeedsModel.Activity.RUN
const SWIM := NeedsModel.Activity.SWIM
const EPSILON: float = 1e-3

var _modifiers: NeedModifiers


func before() -> void:
	_modifiers = load("res://data/needs/need_modifiers.tres")


func _model() -> NeedsModel:
	var definitions: Array[NeedDefinition] = []
	for id in IDS:
		definitions.append(load("res://data/needs/%s.tres" % id))
	return NeedsModel.new(definitions, _modifiers)


func _minutes(model: NeedsModel, minutes: float, activity: int, warmth: float) -> void:
	# 4 Hz, like the component.
	for i in int(minutes * 60.0 * 4.0):
		model.tick(0.25, activity, warmth)


# --- decay rates --------------------------------------------------------------------------


func test_needs_start_full_and_not_critical() -> void:
	var model := _model()
	for id in IDS:
		assert_float(model.fraction(id)).is_equal(1.0)
		assert_bool(model.is_critical(id)).is_false()


func test_trotting_decays_at_the_defined_rate() -> void:
	var model := _model()
	_minutes(model, 1.0, TROT, 0.0)
	for id: StringName in [&"hunger", &"thirst", &"energy"]:
		var expected: float = 100.0 - model.definition(id).decay_per_minute
		assert_float(model.value(id)).is_equal_approx(expected, EPSILON)
	# Neutral biome, trotting: no heat.
	assert_float(model.value(&"temperature")).is_equal_approx(100.0, EPSILON)


func test_thirst_turns_critical_after_eight_minutes_of_trotting() -> void:
	var model := _model()
	_minutes(model, 7.9, TROT, 0.0)
	assert_bool(model.is_critical(&"thirst")).is_false()
	_minutes(model, 0.2, TROT, 0.0)
	assert_bool(model.is_critical(&"thirst")).is_true()


# --- clamping -----------------------------------------------------------------------------


func test_values_clamp_at_zero() -> void:
	var model := _model()
	_minutes(model, 30.0, RUN, 1.0)
	for id in IDS:
		assert_float(model.value(id)).is_equal(0.0)


func test_values_clamp_at_max() -> void:
	var model := _model()
	_minutes(model, 5.0, IDLE, -1.0)  # energy and comfort recover while full
	assert_float(model.value(&"energy")).is_equal(100.0)
	assert_float(model.value(&"temperature")).is_equal(100.0)
	model.set_value(&"hunger", 500.0)
	assert_float(model.value(&"hunger")).is_equal(100.0)
	model.set_value(&"hunger", -5.0)
	assert_float(model.value(&"hunger")).is_equal(0.0)


# --- modifiers ----------------------------------------------------------------------------


func test_running_drains_energy_and_thirst_faster_than_trotting() -> void:
	var model := _model()
	for id: StringName in [&"energy", &"thirst"]:
		assert_float(model.rate_for(id, RUN, 0.0)).is_less(model.rate_for(id, TROT, 0.0))


func test_idle_drains_food_and_water_slower_and_recovers_energy() -> void:
	var model := _model()
	for id: StringName in [&"hunger", &"thirst"]:
		assert_float(model.rate_for(id, IDLE, 0.0)).is_greater(model.rate_for(id, TROT, 0.0))
		assert_float(model.rate_for(id, IDLE, 0.0)).is_less(0.0)
	assert_float(model.rate_for(&"energy", IDLE, 0.0)).is_greater(0.0)
	model.set_value(&"energy", 20.0)
	_minutes(model, 1.0, IDLE, 0.0)
	assert_float(model.value(&"energy")).is_greater(20.0)


func test_warm_biomes_lower_comfort_and_cool_biomes_restore_it() -> void:
	var model := _model()
	assert_float(model.rate_for(&"temperature", TROT, 1.0)).is_less(0.0)
	assert_float(model.rate_for(&"temperature", TROT, -0.5)).is_greater(0.0)
	# Hills (warmth 1) while trotting: 10 minutes to critical (the chosen pacing).
	var need := model.definition(&"temperature")
	var minutes := (
		(need.max_value - need.critical_threshold) / -model.rate_for(&"temperature", TROT, 1.0)
	)
	assert_float(minutes).is_equal_approx(10.0, 0.5)


func test_running_heats_up_and_water_cools_down() -> void:
	var model := _model()
	assert_float(model.rate_for(&"temperature", RUN, 0.0)).is_less(0.0)
	assert_float(model.rate_for(&"temperature", RUN, 0.0)).is_less(
		model.rate_for(&"temperature", TROT, 0.0)
	)
	# In water comfort recovers even in the warmest biome and while swimming.
	assert_float(model.rate_for(&"temperature", SWIM, 1.0, true)).is_greater(0.0)
	assert_float(model.rate_for(&"temperature", TROT, 1.0, true)).is_greater(
		model.rate_for(&"temperature", TROT, -1.0)
	)


# --- critical signals ---------------------------------------------------------------------


func test_critical_fires_once_when_crossing_the_threshold() -> void:
	var model := _model()
	var entered: Array[StringName] = []
	model.critical_entered.connect(func(id: StringName) -> void: entered.append(id))
	_minutes(model, 9.0, TROT, 0.0)
	_minutes(model, 3.0, TROT, 0.0)  # stays critical: no repeat
	assert_array(entered).contains_exactly([&"thirst"])


func test_recovery_needs_the_margin_above_the_threshold() -> void:
	var model := _model()
	var exited: Array[StringName] = []
	model.critical_exited.connect(func(id: StringName) -> void: exited.append(id))
	model.set_value(&"energy", 20.0)
	assert_bool(model.is_critical(&"energy")).is_true()
	model.set_value(&"energy", 30.0)  # above the threshold, within the margin
	assert_bool(model.is_critical(&"energy")).is_true()
	assert_array(exited).is_empty()
	model.set_value(&"energy", 36.0)
	assert_bool(model.is_critical(&"energy")).is_false()
	assert_array(exited).contains_exactly([&"energy"])


func test_refill_recovers_every_critical_need() -> void:
	var model := _model()
	_minutes(model, 30.0, RUN, 1.0)
	var exited: Array[StringName] = []
	model.critical_exited.connect(func(id: StringName) -> void: exited.append(id))
	model.refill_all()
	assert_int(exited.size()).is_equal(IDS.size())
	for id in IDS:
		assert_float(model.fraction(id)).is_equal(1.0)


func test_value_changed_reports_new_values_only() -> void:
	var model := _model()
	var changes: Array = []
	model.value_changed.connect(func(id: StringName, v: float) -> void: changes.append([id, v]))
	model.tick(0.25, IDLE, -1.0)  # full energy and comfort cannot rise: only hunger/thirst
	assert_int(changes.size()).is_equal(2)
	model.set_value(&"hunger", model.value(&"hunger"))
	assert_int(changes.size()).is_equal(2)
