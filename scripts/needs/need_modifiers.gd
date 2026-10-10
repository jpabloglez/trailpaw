class_name NeedModifiers
extends Resource
## How activity, biome and water change need rates. Lives at
## [code]data/needs/need_modifiers.tres[/code].
##
## Every need but [member warmth_need] changes at [code]-decay_per_minute × multiplier[/code],
## with the multiplier of the current activity (missing = 1; negative = recovery, e.g. energy
## while idle). [member warmth_need] follows the felt warmth instead:
## [code]-decay_per_minute × (biome warmth + activity heat)[/code], and in water the felt warmth
## is [member water_warmth]. Positive warmth lowers comfort, negative restores it, down to
## [member cold_knee]: colder than that, comfort recovers less and less and then drops (too
## cold; in practice only on the mountain snow, Phase 17).

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
## Warmth added at midnight (the coolest hour; eased towards [member noon_warmth] with the day).
@export_range(-2.0, 2.0, 0.05) var night_warmth: float = 0.0
## Warmth added at noon (the warmest hour).
@export_range(-2.0, 2.0, 0.05) var noon_warmth: float = 0.0
## Warmth added by the weather: clear, cloudy, rain.
@export var weather_warmth: Vector3 = Vector3.ZERO
@export_group("Cold")
## Warmth added while standing on snow (above [member TerrainSettings.snow_line]).
@export_range(-5.0, 0.0, 0.05) var snow_warmth: float = 0.0
## Felt warmth that refreshes the most; colder feels worse ([method comfort_warmth]).
@export_range(-5.0, 0.0, 0.05) var cold_knee: float = -5.0
## How fast comfort turns from recovering to dropping below [member cold_knee].
@export_range(0.1, 10.0, 0.1) var cold_steepness: float = 1.0

@export_group("Rain")
## Need id → rate multiplier while it rains (e.g. less thirst).
@export var rain: Dictionary[StringName, float] = {}

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


## Warmth the time of day adds at [param hour] (0…24): [member night_warmth] at midnight,
## [member noon_warmth] at noon, eased with a cosine in between.
func time_warmth(hour: float) -> float:
	var t := (cos((hour - 12.0) / 24.0 * TAU) + 1.0) * 0.5
	return lerpf(night_warmth, noon_warmth, t)


## Warmth the weather adds ([code]&"clear"[/code], [code]&"cloudy"[/code], [code]&"rain"[/code]).
func weather_warmth_for(weather: StringName) -> float:
	match weather:
		&"cloudy":
			return weather_warmth.y
		&"rain":
			return weather_warmth.z
	return weather_warmth.x


## The warmth comfort reacts to for a felt warmth of [param felt]: [param felt] itself down to
## [member cold_knee], then rising again with [member cold_steepness] (positive = too cold).
## Continuous; the identity for every felt warmth above the knee.
func comfort_warmth(felt: float) -> float:
	if felt >= cold_knee:
		return felt
	return cold_knee + (cold_knee - felt) * cold_steepness


## Whether a felt warmth of [param felt] is too cold (comfort drops).
func is_too_cold(felt: float) -> bool:
	return felt < cold_knee and comfort_warmth(felt) > 0.0


## Warmth added by [param activity] (see [enum NeedsModel.Activity]).
func heat(activity: int) -> float:
	return activity_heat.get(NeedsModel.ACTIVITY_NAMES[activity], 0.0)
