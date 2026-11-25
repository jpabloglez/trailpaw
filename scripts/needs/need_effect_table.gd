class_name NeedEffectTable
extends Resource
## Every [NeedEffect] of an animal plus the shared tuning of need effects (ADR-012). Lives at
## [code]data/needs/need_effects.tres[/code]; [NeedEffects] combines it with the needs state.

## The effects, any order.
@export var effects: Array[NeedEffect] = []
## Highest combined drain multiplier one need can get from the others (no runaway spirals).
@export_range(1.0, 5.0, 0.05) var rate_cap: float = 1.0

@export_group("Sprint bursts")
## How long a sprint lasts while sprinting is limited to bursts (seconds).
@export_range(0.5, 30.0, 0.1, "suffix:s") var burst_seconds: float = 4.0
## Pause after a burst before the next one (seconds).
@export_range(0.5, 30.0, 0.1, "suffix:s") var burst_rest_seconds: float = 3.0

@export_group("Feeling well")
## With every need at or above this fraction the animal feels well (bonus).
@export_range(0.0, 1.0, 0.01) var bonus_fraction: float = 1.0
## Speed multiplier while feeling well.
@export_range(1.0, 1.5, 0.01) var bonus_speed_factor: float = 1.0

@export_group("Gentle mode")
## How much of each effect remains in the gentle setting (0 = none, 1 = all).
@export_range(0.0, 1.0, 0.05) var gentle_strength: float = 0.5


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for effect in effects:
		if effect == null:
			errors.append("effects must not contain nulls")
			continue
		for error in effect.get_validation_errors():
			errors.append("%s: %s" % [effect.resource_path.get_file(), error])
		var key := "%s/%d/%d" % [effect.need_id, effect.tier, effect.warmth]
		if seen.has(key):
			errors.append("duplicate effect for %s" % key)
		seen[key] = true
	return errors
