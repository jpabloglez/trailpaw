class_name AmbienceLayer
extends Resource
## One looping ambience sound and how loud it plays: per biome by day and by night, and how
## rain changes it (drowned out, or the rain itself). Part of [AmbienceSettings].

## The looping sound.
@export var stream: AudioStream
## Biome id → volume (linear 0…1) by day; missing biomes are silent.
@export var day: Dictionary[StringName, float] = {}
## Biome id → volume (linear 0…1) at night.
@export var night: Dictionary[StringName, float] = {}
## Volume multiplier at full rain (1 = unaffected, 0.3 = mostly drowned out).
@export_range(0.0, 1.0, 0.01) var under_rain: float = 1.0
## Whether this layer is the rain itself (its volume follows the rain, in every biome).
@export var is_rain: bool = false
## Volume of the rain layer at full rain.
@export_range(0.0, 1.0, 0.01) var rain_volume: float = 0.0


## Target volume in [param biome] with [param daylight] (0 night … 1 day) and [param rain]
## (0…1).
func volume_for(biome: StringName, daylight: float, rain: float) -> float:
	if is_rain:
		return rain_volume * rain
	var base := lerpf(night.get(biome, 0.0), day.get(biome, 0.0), daylight)
	return base * lerpf(1.0, under_rain, rain)
