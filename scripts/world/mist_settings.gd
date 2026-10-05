class_name MistSettings
extends Resource
## Morning mist ([Mist]): where, when and how thick. Values live in
## [code]data/world/mist.tres[/code].

## Biome id → how much mist it gets at full strength (0…1); missing biomes get none.
@export var biomes: Dictionary[StringName, float] = {}
## Hours (0…24, rising) of the [member amount] keys.
@export var key_hours := PackedFloat32Array()
## Mist strength (0…1) at each of [member key_hours] (linear in between, 0 outside).
@export var amount := PackedFloat32Array()
## Fog depth distances (m) at full mist (the environment's own apply with none).
@export_range(0.0, 500.0, 1.0, "suffix:m") var depth_begin: float = 12.0
@export_range(0.0, 1000.0, 1.0, "suffix:m") var depth_end: float = 70.0
## Mist colour, mixed into the day/night fog colour by up to [member color_mix].
@export var color := Color(0.85, 0.87, 0.88)
@export_range(0.0, 1.0, 0.01) var color_mix: float = 0.6
## How fast the mist follows its target (fraction per second), so walking in and out of the
## wetland or a jump of the clock fades it rather than switching it.
@export_range(0.01, 5.0, 0.01) var response: float = 0.35


## Mist strength by the hour alone (0…1) at [param hour].
func hour_amount(hour: float) -> float:
	if key_hours.is_empty() or hour < key_hours[0] or hour > key_hours[key_hours.size() - 1]:
		return 0.0
	return DayCurve.sample(key_hours, amount, hour)


## Problems with this resource (empty when valid).
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if key_hours.size() != amount.size() or key_hours.size() < 2:
		errors.append("key_hours and amount must have the same size (≥ 2)")
	for i in range(1, key_hours.size()):
		if key_hours[i] <= key_hours[i - 1]:
			errors.append("key_hours must rise")
	if depth_begin >= depth_end:
		errors.append("depth_begin must be < depth_end")
	return errors
