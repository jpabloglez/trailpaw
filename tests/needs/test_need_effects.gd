## Tests for [NeedEffects]: combining the active effects of the shipped table, the
## feeling-well bonus, the drain cap and the intensity setting (ADR-012).
extends GdUnitTestSuite

const IDS: Array[StringName] = [&"hunger", &"thirst", &"temperature", &"energy"]
const SPRINT_FULL := NeedEffect.Sprint.FULL
const SPRINT_BURSTS := NeedEffect.Sprint.BURSTS
const SPRINT_NONE := NeedEffect.Sprint.NONE
const GENTLE := NeedEffects.Intensity.GENTLE
const OFF := NeedEffects.Intensity.OFF

var _table: NeedEffectTable


func before() -> void:
	_table = load("res://data/needs/need_effects.tres")


func _model() -> NeedsModel:
	var definitions: Array[NeedDefinition] = []
	for id in IDS:
		definitions.append(load("res://data/needs/%s.tres" % id))
	return NeedsModel.new(definitions, load("res://data/needs/need_modifiers.tres"))


func _effects(model: NeedsModel, cold := false, shaded := false, intensity := 2) -> NeedEffects:
	var effects := NeedEffects.new(_table)
	effects.update(model, cold, shaded, intensity)
	return effects


func test_full_needs_feel_well() -> void:
	var effects := _effects(_model())
	assert_bool(effects.feeling_well).is_true()
	assert_float(effects.speed_factor).is_equal(_table.bonus_speed_factor)
	assert_int(effects.sprint).is_equal(SPRINT_FULL)
	assert_array(effects.cues()).is_empty()


func test_middling_needs_are_neutral() -> void:
	var model := _model()
	model.set_value(&"hunger", 50.0)
	var effects := _effects(model)
	assert_bool(effects.feeling_well).is_false()
	assert_float(effects.speed_factor).is_equal(1.0)
	assert_float(effects.jump_factor).is_equal(1.0)
	assert_float(effects.rate_multiplier(&"energy")).is_equal(1.0)


func test_low_thirst_limits_sprints_to_bursts_and_pants() -> void:
	var model := _model()
	model.set_value(&"thirst", 20.0)
	var effects := _effects(model)
	assert_int(effects.sprint).is_equal(SPRINT_BURSTS)
	assert_array(effects.sprint_limiters()).is_equal([&"thirst"])
	assert_float(effects.rate_multiplier(&"temperature")).is_equal_approx(1.3, 1e-4)
	assert_float(effects.sniff_factor(&"water")).is_equal(1.5)
	assert_array(effects.cues()).contains([&"pant"])


func test_empty_thirst_stops_sprinting() -> void:
	var model := _model()
	model.set_value(&"thirst", 0.0)
	var effects := _effects(model)
	assert_int(effects.sprint).is_equal(SPRINT_NONE)
	assert_float(effects.rate_multiplier(&"temperature")).is_equal_approx(1.6, 1e-4)


func test_hunger_slows_rest_and_helps_the_nose() -> void:
	var model := _model()
	model.set_value(&"hunger", 0.0)
	var effects := _effects(model)
	assert_float(effects.rest_factor).is_equal(0.5)
	assert_float(effects.rate_multiplier(&"energy")).is_equal_approx(1.6, 1e-4)
	assert_float(effects.sniff_factor(&"food")).is_equal(1.5)
	assert_int(effects.sprint).is_equal(SPRINT_FULL)


func test_empty_energy_takes_jumps_and_sprints() -> void:
	var model := _model()
	model.set_value(&"energy", 0.0)
	var effects := _effects(model)
	assert_int(effects.sprint).is_equal(SPRINT_NONE)
	assert_float(effects.jump_factor).is_equal(0.5)
	assert_float(effects.speed_factor).is_equal(0.9)
	assert_array(effects.cues()).is_equal([&"tired"])


func test_heat_pauses_in_the_shade_but_cold_does_not() -> void:
	var model := _model()
	model.set_value(&"temperature", 20.0)
	assert_float(_effects(model).speed_factor).is_equal(0.9)
	assert_float(_effects(model, false, true).speed_factor).is_equal(1.0)
	var cold := _effects(model, true, true)
	assert_float(cold.rate_multiplier(&"energy")).is_equal_approx(1.3, 1e-4)
	assert_array(cold.cues()).is_equal([&"shiver"])


func test_drain_multipliers_stack_up_to_the_cap() -> void:
	var model := _model()
	model.set_value(&"hunger", 0.0)  # energy ×1.6
	model.set_value(&"temperature", 0.0)  # cold: energy ×1.6
	var effects := _effects(model, true)
	assert_float(effects.rate_multiplier(&"energy")).is_equal(_table.rate_cap)


func test_the_lowest_factor_and_strictest_sprint_win() -> void:
	var model := _model()
	model.set_value(&"thirst", 20.0)  # bursts
	model.set_value(&"energy", 0.0)  # none, jump 0.5
	model.set_value(&"temperature", 0.0)  # cold, jump 0.75
	var effects := _effects(model, true)
	assert_int(effects.sprint).is_equal(SPRINT_NONE)
	assert_float(effects.jump_factor).is_equal(0.5)
	assert_array(effects.sprint_limiters()).contains_exactly_in_any_order([&"thirst", &"energy"])
	assert_array(effects.cues()).contains_exactly_in_any_order([&"pant", &"tired", &"shiver"])


func test_gentle_halves_effects_and_never_blocks_sprinting() -> void:
	var model := _model()
	model.set_value(&"energy", 0.0)
	model.set_value(&"hunger", 0.0)
	var effects := _effects(model, false, false, GENTLE)
	assert_int(effects.sprint).is_equal(SPRINT_BURSTS)
	assert_float(effects.jump_factor).is_equal_approx(0.75, 1e-4)
	assert_float(effects.rate_multiplier(&"energy")).is_equal_approx(1.3, 1e-4)
	assert_float(effects.sniff_factor(&"food")).is_equal(1.5)


func test_off_keeps_only_cues_and_the_nose() -> void:
	var model := _model()
	model.set_value(&"thirst", 0.0)
	model.set_value(&"energy", 0.0)
	var effects := _effects(model, false, false, OFF)
	assert_int(effects.sprint).is_equal(SPRINT_FULL)
	assert_float(effects.speed_factor).is_equal(1.0)
	assert_float(effects.jump_factor).is_equal(1.0)
	assert_float(effects.rate_multiplier(&"temperature")).is_equal(1.0)
	assert_array(effects.sprint_limiters()).is_empty()
	assert_float(effects.sniff_factor(&"water")).is_equal(1.5)
	assert_array(effects.cues()).contains_exactly_in_any_order([&"pant", &"tired"])


func test_updating_again_resets_what_no_longer_applies() -> void:
	var model := _model()
	model.set_value(&"thirst", 0.0)
	var effects := _effects(model)
	model.refill_all()
	effects.update(model, false, false)
	assert_int(effects.sprint).is_equal(SPRINT_FULL)
	assert_array(effects.cues()).is_empty()
	assert_float(effects.rate_multiplier(&"temperature")).is_equal(1.0)
	assert_bool(effects.feeling_well).is_true()


func test_drains_speed_up_only_needs_that_are_dropping() -> void:
	var model := _model()
	model.set_value(&"hunger", 0.0)  # energy drains ×1.6
	var effects := _effects(model)
	var plain := _model()
	plain.set_value(&"hunger", 0.0)
	model.set_value(&"energy", 50.0)
	plain.set_value(&"energy", 50.0)
	for i in 240:  # a minute of trotting
		model.tick(0.25, NeedsModel.Activity.TROT, 0.0, false, false, {}, effects)
		plain.tick(0.25, NeedsModel.Activity.TROT, 0.0)
	var decay: float = model.definition(&"energy").decay_per_minute
	assert_float(50.0 - model.value(&"energy")).is_equal_approx(decay * 1.6, 1e-2)
	assert_float(50.0 - plain.value(&"energy")).is_equal_approx(decay, 1e-2)
	for i in 240:  # resting still: recovery is not slowed
		model.tick(0.25, NeedsModel.Activity.IDLE, 0.0, false, false, {}, effects)
		plain.tick(0.25, NeedsModel.Activity.IDLE, 0.0)
	var model_gain := model.value(&"energy")
	assert_float(model_gain - (50.0 - decay * 1.6)).is_equal_approx(
		plain.value(&"energy") - (50.0 - decay), 1e-2
	)
