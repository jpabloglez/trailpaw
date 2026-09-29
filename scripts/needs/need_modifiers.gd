class_name NeedModifiers
extends Resource
## How activity, biome and water change need rates. Lives at
## [code]data/needs/need_modifiers.tres[/code].
##
## Every need but [member warmth_need] changes at [code]-decay_per_minute × multiplier[/code],
## with the multiplier of the current activity (missing = 1; negative = recovery, e.g. energy
## while idle). [member warmth_need] follows the felt warmth instead:
## [code]-decay_per_minute × (biome warmth + activity heat)[/code], and in water the felt warmth
## is [member water_warmth]. Positive warmth lowers comfort, negative restores it.

## Need driven by warmth rather than activity multipliers.
@export var warmth_need: StringName = &"temperature"
## Need id → rate multiplier while standing still.
@export var idle: Dictionary[StringName, float] = {}
## Need id → rate multiplier while walking.
@export var walk: Dictionary[StringName, float] = {}
## Need id → rate multiplier while trotting (the base pace).
@export var trot: Dictionary[StringName, float] = {}
## Need id → rate multiplier while running.
@export var run: Dictionary[StringName, float] = {}
## Need id → rate multiplier while swimming.
@export var swim: Dictionary[StringName, float] = {}

@export_group("Warmth")
## Warmth added by each activity (exertion heats, resting cools a little); keys are
## [code]idle walk trot run swim[/code].
@export var activity_heat: Dictionary[StringName, float] = {}
## Felt warmth while in water (replaces biome warmth and activity heat).
@export_range(-5.0, 0.0, 0.05) var water_warmth: float = 0.0

@export_group("Effects")
## How fast the movement slowdown of critical needs eases in and out (multiplier per second).
@export_range(0.01, 10.0, 0.01, "suffix:1/s") var speed_ease_per_second: float = 0.1
## How fast the tired look eases in and out (blend per second).
@export_range(0.01, 10.0, 0.01, "suffix:1/s") var tired_ease_per_second: float = 0.5


## Rate multiplier of [param need_id] for [param activity] (see [enum NeedsModel.Activity]).
func multiplier(need_id: StringName, activity: int) -> float:
	match activity:
		NeedsModel.Activity.IDLE:
			return idle.get(need_id, 1.0)
		NeedsModel.Activity.WALK:
			return walk.get(need_id, 1.0)
		NeedsModel.Activity.RUN:
			return run.get(need_id, 1.0)
		NeedsModel.Activity.SWIM:
			return swim.get(need_id, 1.0)
	return trot.get(need_id, 1.0)


## Warmth added by [param activity] (see [enum NeedsModel.Activity]).
func heat(activity: int) -> float:
	return activity_heat.get(NeedsModel.ACTIVITY_NAMES[activity], 0.0)
