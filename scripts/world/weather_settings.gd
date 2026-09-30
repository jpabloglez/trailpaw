class_name WeatherSettings
extends Resource
## Weather pacing and looks. Values live in [code]data/world/weather.tres[/code].

@export_group("Chain")
## Game minutes per weather slot.
@export_range(1.0, 1440.0, 1.0, "suffix:min") var slot_minutes: float = 60.0
## Transition probabilities from CLEAR to (clear, cloudy, rain); rows sum to 1.
@export var from_clear: Vector3 = Vector3(1, 0, 0)
## From CLOUDY.
@export var from_cloudy: Vector3 = Vector3(0, 1, 0)
## From RAIN.
@export var from_rain: Vector3 = Vector3(0, 0, 1)

@export_group("Looks")
## Cloud cover per state (clear, cloudy, rain).
@export var cloudiness: Vector3 = Vector3(0.15, 0.65, 0.9)
## Change per game minute of cloud cover and rain (easing between states).
@export_range(0.001, 1.0, 0.001, "suffix:1/min") var ease_per_minute: float = 0.05
## Ground wetting per game minute while it rains.
@export_range(0.001, 1.0, 0.001, "suffix:1/min") var wet_per_minute: float = 0.05
## Ground drying per game minute otherwise.
@export_range(0.0001, 1.0, 0.0001, "suffix:1/min") var dry_per_minute: float = 0.008
## Sunlight kept under full cloud cover.
@export_range(0.0, 1.0, 0.01) var overcast_sun: float = 0.45
## Extra wind strength factor at full rain.
@export_range(0.0, 3.0, 0.05) var rain_wind: float = 0.8
## Rain drops at full rain.
@export_range(0, 20000, 100) var rain_drops: int = 3000


## The chain rows in state order.
func transitions() -> Array[Vector3]:
	return [from_clear, from_cloudy, from_rain]


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for row in transitions():
		if absf(row.x + row.y + row.z - 1.0) > 1e-4 or row.x < 0 or row.y < 0 or row.z < 0:
			errors.append("each transition row must be probabilities summing to 1")
			break
	if from_clear.z > 0.0:
		errors.append("clear skies must cloud over before it rains (from_clear.z = 0)")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
