## Tests for [NeedEffect] / [NeedEffectTable]: validation, when an effect applies, and the
## shipped table in data/needs/need_effects.tres (ADR-012).
extends GdUnitTestSuite

const LOW := NeedsModel.Tier.LOW
const EMPTY := NeedsModel.Tier.EMPTY
const NEEDS: Array[StringName] = [&"hunger", &"thirst", &"temperature", &"energy"]


func _table() -> NeedEffectTable:
	return load("res://data/needs/need_effects.tres") as NeedEffectTable


func _effect(need_id: StringName, tier: NeedsModel.Tier) -> NeedEffect:
	var effect := NeedEffect.new()
	effect.need_id = need_id
	effect.tier = tier
	return effect


func test_the_shipped_table_is_valid() -> void:
	var table := _table()
	assert_object(table).is_not_null()
	assert_array(Array(table.get_validation_errors())).is_empty()
	assert_float(table.rate_cap).is_between(1.0, 2.0)
	assert_float(table.bonus_speed_factor).is_between(1.0, 1.1)


func test_every_need_has_a_low_and_an_empty_effect() -> void:
	var found := {}
	for effect in _table().effects:
		found["%s/%d" % [effect.need_id, effect.tier]] = true
	for id in NEEDS:
		assert_bool(found.has("%s/%d" % [id, LOW])).is_true()
		assert_bool(found.has("%s/%d" % [id, EMPTY])).is_true()


func test_effects_never_stop_walking_or_trotting_much() -> void:
	# Only extras are taken away (ADR-012): speed stays at 90 % or more.
	for effect in _table().effects:
		assert_float(effect.speed_factor).is_greater_equal(0.9)
		assert_bool(effect.cue != &"").is_true()


func test_neutral_effect_is_invalid_without_a_need_or_tier() -> void:
	assert_bool(NeedEffect.new().is_valid()).is_false()
	assert_bool(_effect(&"thirst", LOW).is_valid()).is_true()
	assert_bool(_effect(&"thirst", NeedsModel.Tier.NORMAL).is_valid()).is_false()


func test_validation_rejects_self_drain_and_relief_multipliers() -> void:
	var effect := _effect(&"thirst", LOW)
	effect.rate_multipliers = {&"thirst": 1.5}
	assert_bool(effect.is_valid()).is_false()
	effect.rate_multipliers = {&"energy": 0.5}
	assert_bool(effect.is_valid()).is_false()
	effect.rate_multipliers = {&"energy": 1.5}
	effect.sniff_factors = {&"water": 0.5}
	assert_bool(effect.is_valid()).is_false()


func test_table_rejects_duplicates() -> void:
	var table := NeedEffectTable.new()
	table.effects = [_effect(&"thirst", LOW), _effect(&"thirst", LOW)]
	assert_array(Array(table.get_validation_errors())).is_not_empty()


func test_applies_only_at_its_own_tier() -> void:
	var effect := _effect(&"thirst", LOW)
	assert_bool(effect.applies(LOW, false, false)).is_true()
	assert_bool(effect.applies(EMPTY, false, false)).is_false()
	assert_bool(effect.applies(NeedsModel.Tier.NORMAL, false, false)).is_false()


func test_warmth_and_shade_conditions() -> void:
	var hot := _effect(&"temperature", LOW)
	hot.warmth = NeedEffect.Warmth.HOT
	hot.lifted_in_shade = true
	assert_bool(hot.applies(LOW, false, false)).is_true()
	assert_bool(hot.applies(LOW, true, false)).is_false()  # cold: not this effect
	assert_bool(hot.applies(LOW, false, true)).is_false()  # in the shade: paused
	var cold := _effect(&"temperature", LOW)
	cold.warmth = NeedEffect.Warmth.COLD
	assert_bool(cold.applies(LOW, true, true)).is_true()
	assert_bool(cold.applies(LOW, false, false)).is_false()
