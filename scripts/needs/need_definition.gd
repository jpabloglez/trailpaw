class_name NeedDefinition
extends Resource
## Data for one need (hunger, thirst, temperature comfort, energy). Lives under
## [code]data/needs/[/code].
##
## A need's value runs from 0 to [member max_value] and starts full; lower means needier (for
## temperature comfort, lower means hotter). [member decay_per_minute] is the base rate while
## trotting in neutral conditions; activity and biome modifiers scale it ([code]NeedsModel[/code]).
## At or below [member critical_threshold] the need is critical and soft consequences apply
## (ADR-003: no death); it stops being critical only above threshold + [member recover_margin].
## [br][br]
## Defaults are neutral: values come from data (see [method get_validation_errors]).

## Stable identifier used in events and saves (e.g. [code]&"thirst"[/code]).
@export var id: StringName = &""
## Name shown to the player.
@export var display_name: String = ""
## HUD icon (set with the needs HUD).
@export var icon: Texture2D
## Value when fully satisfied (the need starts here).
@export_range(1.0, 1000.0, 1.0) var max_value: float = 0.0
## Base loss per minute while trotting in neutral conditions.
@export_range(0.0, 100.0, 0.001, "suffix:/min") var decay_per_minute: float = 0.0
## At or below this value the need is critical.
@export_range(0.0, 1000.0, 0.5) var critical_threshold: float = 0.0
## A critical need recovers only above threshold + this (hysteresis: no flicker).
@export_range(0.0, 1000.0, 0.5) var recover_margin: float = 0.0

@export_group("Effects when critical")
## Movement speed multiplier while this need is critical (1 = no slowdown).
@export_range(0.1, 1.0, 0.01) var critical_speed_factor: float = 1.0
## Whether the animal looks tired (tired idle animation) while this need is critical.
@export var tired_when_critical: bool = false


## Minutes of steady trotting in neutral conditions from full to critical.
func minutes_to_critical() -> float:
	if decay_per_minute <= 0.0:
		return INF
	return (max_value - critical_threshold) / decay_per_minute


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if max_value <= 0.0:
		errors.append("max_value must be > 0")
	if decay_per_minute <= 0.0:
		errors.append("decay_per_minute must be > 0")
	if critical_threshold <= 0.0 or critical_threshold + recover_margin >= max_value:
		errors.append("thresholds must satisfy 0 < critical_threshold + recover_margin < max")
	if recover_margin <= 0.0:
		errors.append("recover_margin must be > 0")
	if critical_speed_factor <= 0.0 or critical_speed_factor > 1.0:
		errors.append("critical_speed_factor must be within (0, 1]")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
