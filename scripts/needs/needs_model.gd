class_name NeedsModel
extends RefCounted
## Pure needs logic: values, decay and recovery rates, clamping and critical states with
## hysteresis. [code]NeedsComponent[/code] feeds it activity and warmth at a fixed tick rate.
##
## Values run from 0 to each [member NeedDefinition.max_value] and start full. A need becomes
## critical at or below its threshold and recovers only above threshold + recover margin, so
## [signal critical_entered] and [signal critical_exited] fire once per crossing.
## [br][br]
## Each need also has a [enum Tier] (ADR-012): [constant NORMAL], [constant LOW] while critical
## and [constant EMPTY] at 0, until it rises above
## [member NeedDefinition.empty_recover_margin]. [signal tier_changed] fires once per change.
## [br][br]
## Budget: O(needs) float ops per [method tick]; no allocations.

## A need's value changed.
signal value_changed(need_id: StringName, value: float)
## A need reached its critical threshold.
signal critical_entered(need_id: StringName)
## A critical need rose above threshold + recover margin.
signal critical_exited(need_id: StringName)
## A need's [enum Tier] changed.
signal tier_changed(need_id: StringName, tier: Tier)

## What the animal is doing, as far as needs are concerned.
enum Activity { IDLE, WALK, TROT, RUN, SWIM }
## How depleted a need is: fine, low (critical) or empty (at 0). Effects key on it (ADR-012).
enum Tier { NORMAL, LOW, EMPTY }

## [enum Activity] names used as keys in [NeedModifiers] data.
const ACTIVITY_NAMES: Array[StringName] = [&"idle", &"walk", &"trot", &"run", &"swim"]

var _definitions: Array[NeedDefinition] = []
var _modifiers: NeedModifiers
var _index: Dictionary[StringName, int] = {}
var _values: PackedFloat32Array = PackedFloat32Array()
var _critical: Array[bool] = []
var _empty: Array[bool] = []


func _init(definitions: Array[NeedDefinition], modifiers: NeedModifiers) -> void:
	_definitions = definitions
	_modifiers = modifiers
	for i in definitions.size():
		_index[definitions[i].id] = i
		_values.append(definitions[i].max_value)
		_critical.append(false)
		_empty.append(false)


## Need ids in definition order.
func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for need in _definitions:
		result.append(need.id)
	return result


## Definition of [param need_id].
func definition(need_id: StringName) -> NeedDefinition:
	return _definitions[_index[need_id]]


## Current value of [param need_id].
func value(need_id: StringName) -> float:
	return _values[_index[need_id]]


## Current value of [param need_id] as a fraction of its maximum (0…1).
func fraction(need_id: StringName) -> float:
	var i: int = _index[need_id]
	return _values[i] / _definitions[i].max_value


## Whether [param need_id] is critical.
func is_critical(need_id: StringName) -> bool:
	return _critical[_index[need_id]]


## [enum Tier] of [param need_id].
func tier(need_id: StringName) -> Tier:
	return _tier(_index[need_id])


## Whether every need is at or above [param min_fraction] of its maximum.
func all_at_least(min_fraction: float) -> bool:
	for i in _definitions.size():
		if _values[i] < min_fraction * _definitions[i].max_value:
			return false
	return true


## Number of critical needs.
func critical_count() -> int:
	return _critical.count(true)


## Movement speed multiplier from the critical needs: the lowest
## [member NeedDefinition.critical_speed_factor] among them (1 when none is critical).
func critical_speed_factor() -> float:
	var factor := 1.0
	for i in _definitions.size():
		if _critical[i]:
			factor = minf(factor, _definitions[i].critical_speed_factor)
	return factor


## Whether a critical need makes the animal look tired.
func is_tired() -> bool:
	for i in _definitions.size():
		if _critical[i] and _definitions[i].tired_when_critical:
			return true
	return false


## Sets [param need_id] to [param new_value] (clamped) and updates its critical state now.
func set_value(need_id: StringName, new_value: float) -> void:
	_apply(_index[need_id], new_value)


## Fills every need to its maximum.
func refill_all() -> void:
	for i in _definitions.size():
		_apply(i, _definitions[i].max_value)


## Signed rate of [param need_id] per minute (negative = losing) for [param activity] with a
## felt warmth of [param warmth] (biome + time of day + weather); [param in_water] replaces the
## warmth with the water's; [param raining] applies [member NeedModifiers.rain] (less thirst);
## [param biome_multipliers] (need id → factor) are the biome's
## ([member BiomeDefinition.need_multipliers]; temperature follows the warmth instead).
func rate_for(
	need_id: StringName,
	activity: Activity,
	warmth: float,
	in_water: bool = false,
	raining: bool = false,
	biome_multipliers: Dictionary = {}
) -> float:
	var need := definition(need_id)
	if need_id == _modifiers.warmth_need:
		if in_water:
			return -need.decay_per_minute * _modifiers.water_warmth
		var felt := warmth + _modifiers.heat(activity)
		return -need.decay_per_minute * _modifiers.comfort_warmth(felt)
	var rate := -need.decay_per_minute * _modifiers.multiplier(need_id, activity)
	if raining:
		rate *= _modifiers.rain.get(need_id, 1.0)
	return rate * float(biome_multipliers.get(need_id, 1.0))


## Advances every need by [param delta] seconds.
func tick(
	delta: float,
	activity: Activity,
	warmth: float,
	in_water: bool = false,
	raining: bool = false,
	biome_multipliers: Dictionary = {}
) -> void:
	for i in _definitions.size():
		var rate := rate_for(
			_definitions[i].id, activity, warmth, in_water, raining, biome_multipliers
		)
		_apply(i, _values[i] + rate * delta / 60.0)


func _apply(i: int, new_value: float) -> void:
	var need := _definitions[i]
	var clamped := clampf(new_value, 0.0, need.max_value)
	var before := _tier(i)
	if clamped != _values[i]:
		_values[i] = clamped
		value_changed.emit(need.id, clamped)
	if not _critical[i] and clamped <= need.critical_threshold:
		_critical[i] = true
		critical_entered.emit(need.id)
	elif _critical[i] and clamped > need.critical_threshold + need.recover_margin:
		_critical[i] = false
		critical_exited.emit(need.id)
	if not _empty[i] and clamped <= 0.0:
		_empty[i] = true
	elif _empty[i] and clamped > need.empty_recover_margin:
		_empty[i] = false
	var after := _tier(i)
	if after != before:
		tier_changed.emit(need.id, after)


func _tier(i: int) -> Tier:
	if _empty[i]:
		return Tier.EMPTY
	if _critical[i]:
		return Tier.LOW
	return Tier.NORMAL
