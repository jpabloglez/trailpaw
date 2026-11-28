class_name NeedEffects
extends RefCounted
## Pure combination of the active [NeedEffect]s into what the animal can do now (ADR-012).
##
## [method update] reads each need's [enum NeedsModel.Tier] and picks the effects that apply;
## the result combines them: the lowest speed, jump and rest factors, the most restrictive
## [enum NeedEffect.Sprint], drain multipliers multiplied per need and capped at
## [member NeedEffectTable.rate_cap], and the widest sniff factors. With every need at or
## above [member NeedEffectTable.bonus_fraction] the animal feels well: free sprints and
## [member NeedEffectTable.bonus_speed_factor].
## [br][br]
## [enum Intensity] scales gameplay effects for the player's setting: [constant GENTLE]
## keeps [member NeedEffectTable.gentle_strength] of each and turns "no sprint" into bursts;
## [constant OFF] drops them. Sniff help and body-language cues stay in every mode.
## [br][br]
## Budget: O(effects) per [method update] (called on the needs tick, 4 Hz); reuses its
## containers, so no allocations once warmed up.

## How strongly effects apply (the player's setting).
enum Intensity { OFF, GENTLE, NORMAL }

## Multiplier on every target speed.
var speed_factor: float = 1.0
## Sprinting allowed now.
var sprint: NeedEffect.Sprint = NeedEffect.Sprint.FULL
## Multiplier on the jump height.
var jump_factor: float = 1.0
## Multiplier on how fast resting restores energy.
var rest_factor: float = 1.0
## Whether the animal feels well (every need high).
var feeling_well: bool = false

var _table: NeedEffectTable
var _rates: Dictionary[StringName, float] = {}
var _sniff: Dictionary[StringName, float] = {}
var _cues: Array[StringName] = []
var _sprint_limiters: Array[StringName] = []


func _init(table: NeedEffectTable) -> void:
	_table = table


## [enum Intensity] for a [code]Settings.need_effects[/code] choice ([code]&"normal"[/code],
## [code]&"gentle"[/code], [code]&"off"[/code]; anything else is normal).
static func intensity_for(choice: StringName) -> Intensity:
	match choice:
		&"gentle":
			return Intensity.GENTLE
		&"off":
			return Intensity.OFF
	return Intensity.NORMAL


## Recomputes the combined effects from [param model]; the animal is [param cold] (else
## any low comfort is heat) and [param shaded] (in shade or water).
func update(
	model: NeedsModel, cold: bool, shaded: bool, intensity: Intensity = Intensity.NORMAL
) -> void:
	_reset()
	var strength := _strength(intensity)
	for effect in _table.effects:
		if effect.applies(model.tier(effect.need_id), cold, shaded):
			_add(effect, strength, intensity)
	feeling_well = model.all_at_least(_table.bonus_fraction)
	if feeling_well:
		speed_factor *= _table.bonus_speed_factor


## Combined drain multiplier of [param need_id] (1 = unchanged; at most the table's cap).
func rate_multiplier(need_id: StringName) -> float:
	return _rates.get(need_id, 1.0)


## Sniff range multiplier for [param kind] ([code]&"food"[/code], [code]&"water"[/code]).
func sniff_factor(kind: StringName) -> float:
	return _sniff.get(kind, 1.0)


## Body-language cues of the active effects (no duplicates).
func cues() -> Array[StringName]:
	return _cues


## Needs whose effects limit sprinting now (for feedback on a blocked sprint).
func sprint_limiters() -> Array[StringName]:
	return _sprint_limiters


func _add(effect: NeedEffect, strength: float, intensity: Intensity) -> void:
	if effect.cue != &"" and not _cues.has(effect.cue):
		_cues.append(effect.cue)
	for kind: StringName in effect.sniff_factors:
		_sniff[kind] = maxf(_sniff.get(kind, 1.0), effect.sniff_factors[kind])
	if strength <= 0.0:
		return
	speed_factor = minf(speed_factor, lerpf(1.0, effect.speed_factor, strength))
	jump_factor = minf(jump_factor, lerpf(1.0, effect.jump_factor, strength))
	rest_factor = minf(rest_factor, lerpf(1.0, effect.rest_factor, strength))
	var limit := effect.sprint
	if intensity == Intensity.GENTLE and limit == NeedEffect.Sprint.NONE:
		limit = NeedEffect.Sprint.BURSTS
	if limit != NeedEffect.Sprint.FULL:
		sprint = maxi(sprint, limit) as NeedEffect.Sprint
		if not _sprint_limiters.has(effect.need_id):
			_sprint_limiters.append(effect.need_id)
	for id: StringName in effect.rate_multipliers:
		var scaled := lerpf(1.0, effect.rate_multipliers[id], strength)
		_rates[id] = minf(_rates.get(id, 1.0) * scaled, _table.rate_cap)


func _strength(intensity: Intensity) -> float:
	match intensity:
		Intensity.OFF:
			return 0.0
		Intensity.GENTLE:
			return _table.gentle_strength
	return 1.0


func _reset() -> void:
	speed_factor = 1.0
	sprint = NeedEffect.Sprint.FULL
	jump_factor = 1.0
	rest_factor = 1.0
	_rates.clear()
	_sniff.clear()
	_cues.clear()
	_sprint_limiters.clear()
	feeling_well = false
