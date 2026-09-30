class_name DayNightSettings
extends Resource
## How light and sky change over the day ([DayNightCycle]). Every track has one value per key of
## [member key_hours]; values between keys are interpolated, wrapping around midnight
## ([DayCurve]). Values live in [code]data/world/day_night.tres[/code].

@export_group("Sun path")
## Hour the sun rises (crosses the horizon going up).
@export_range(0.0, 12.0, 0.1) var sunrise_hour: float = 6.0
## Hour the sun sets.
@export_range(12.0, 24.0, 0.1) var sunset_hour: float = 18.0
## Highest sun elevation (at the middle of the day).
@export_range(5.0, 90.0, 1.0, "suffix:°") var max_elevation: float = 60.0

@export_group("Tracks")
## Hours of the keys, ascending, in [0, 24).
@export var key_hours := PackedFloat32Array()
## Sunlight energy per key.
@export var sun_energy := PackedFloat32Array()
## Sunlight colour per key.
@export var sun_color := PackedColorArray()
## Moonlight energy per key.
@export var moon_energy := PackedFloat32Array()
## Moonlight colour (constant).
@export var moon_color: Color = Color(0.6, 0.7, 1.0)
## Ambient light energy per key.
@export var ambient_energy := PackedFloat32Array()
## Ambient light colour per key.
@export var ambient_color := PackedColorArray()
## Sky colour overhead per key.
@export var sky_top := PackedColorArray()
## Sky colour at the horizon per key.
@export var sky_horizon := PackedColorArray()
## Fog colour per key (matches the horizon so the streaming edge dissolves into the sky).
@export var fog_color := PackedColorArray()
## How much fog covers the sky (0 = the sky shader shows fully).
@export_range(0.0, 1.0, 0.01) var fog_sky_affect: float = 0.35
## Star visibility (0…1) per key.
@export var stars := PackedFloat32Array()

@export_group("Readability")
## The night stays readable: ambient luminance × energy never goes below this.
@export_range(0.0, 1.0, 0.01) var min_ambient_luminance: float = 0.0


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var n := key_hours.size()
	if n < 2:
		errors.append("key_hours needs at least 2 keys")
	for i in range(1, n):
		if key_hours[i] <= key_hours[i - 1]:
			errors.append("key_hours must be ascending")
			break
	if n > 0 and (key_hours[0] < 0.0 or key_hours[n - 1] >= 24.0):
		errors.append("key_hours must lie in [0, 24)")
	for track: String in [
		"sun_energy",
		"sun_color",
		"moon_energy",
		"ambient_energy",
		"ambient_color",
		"sky_top",
		"sky_horizon",
		"fog_color",
		"stars",
	]:
		if (get(track) as Variant).size() != n:
			errors.append("%s must have one value per key" % track)
	if sunrise_hour >= sunset_hour:
		errors.append("sunrise_hour must be < sunset_hour")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
