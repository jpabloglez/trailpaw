class_name NeedEffect
extends Resource
## What one need does to the animal at one [enum NeedsModel.Tier] (ADR-012). Lives under
## [code]data/needs/effects/[/code] and is listed in a [NeedEffectTable].
##
## An effect applies while its need is exactly at [member tier] (an empty need uses its EMPTY
## effect instead of its LOW one), the warmth matches [member warmth] (comfort runs low from
## heat or from cold) and, with [member lifted_in_shade], the animal is in the sun.
## [br][br]
## Effects only take away extras (sprinting, high jumps, quick rests) or speed other needs up;
## walking, trotting, interacting, resting and sniffing always work. Defaults are neutral.

## How much sprinting an effect allows (higher = more restrictive).
enum Sprint { FULL, BURSTS, NONE }
## Which cause of low comfort an effect answers to.
enum Warmth { ANY, HOT, COLD }

## Need this effect belongs to.
@export var need_id: StringName = &""
## Tier the need must be at ([constant NeedsModel.Tier.LOW] or [constant NeedsModel.Tier.EMPTY]).
@export var tier: NeedsModel.Tier = NeedsModel.Tier.LOW
## Only while too hot ([constant HOT]) or too cold ([constant COLD]); [constant ANY] always.
@export var warmth: Warmth = Warmth.ANY
## The effect pauses in shade or water (heat).
@export var lifted_in_shade: bool = false

@export_group("Movement")
## Multiplier on every target speed.
@export_range(0.1, 1.0, 0.01) var speed_factor: float = 1.0
## Sprinting allowed: freely, in short bursts, or not at all.
@export var sprint: Sprint = Sprint.FULL
## Multiplier on the jump height.
@export_range(0.1, 1.0, 0.01) var jump_factor: float = 1.0

@export_group("Needs")
## Other need id → multiplier on how fast it drains (> 1 = faster).
@export var rate_multipliers: Dictionary[StringName, float] = {}
## Multiplier on how fast resting restores energy.
@export_range(0.1, 1.0, 0.01) var rest_factor: float = 1.0

@export_group("Senses and cues")
## Sniff kind ([code]&"food"[/code], [code]&"water"[/code]) → range multiplier (≥ 1: the nose
## helps find the remedy).
@export var sniff_factors: Dictionary[StringName, float] = {}
## Body-language cue the animal shows (e.g. [code]&"pant"[/code], [code]&"shiver"[/code]).
@export var cue: StringName = &""


## Whether this effect applies to a need at [param need_tier] when the animal is
## [param cold] (or too hot otherwise) and [param shaded].
func applies(need_tier: NeedsModel.Tier, cold: bool, shaded: bool) -> bool:
	if need_tier != tier:
		return false
	if warmth == Warmth.HOT and cold or warmth == Warmth.COLD and not cold:
		return false
	return not (lifted_in_shade and shaded)


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if need_id == &"":
		errors.append("need_id must not be empty")
	if tier == NeedsModel.Tier.NORMAL:
		errors.append("tier must be LOW or EMPTY")
	if speed_factor <= 0.0 or speed_factor > 1.0:
		errors.append("speed_factor must be within (0, 1]")
	if jump_factor <= 0.0 or jump_factor > 1.0:
		errors.append("jump_factor must be within (0, 1]")
	if rest_factor <= 0.0 or rest_factor > 1.0:
		errors.append("rest_factor must be within (0, 1]")
	for id: StringName in rate_multipliers:
		if id == need_id:
			errors.append("rate_multipliers must not speed up the need itself")
		if rate_multipliers[id] < 1.0:
			errors.append("rate_multipliers must be >= 1")
	for kind: StringName in sniff_factors:
		if sniff_factors[kind] < 1.0:
			errors.append("sniff_factors must be >= 1")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
