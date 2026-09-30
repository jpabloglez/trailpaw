class_name FaunaProfile
extends Resource
## How an animal reacts and spends its time: the tunables behind [FaunaDecision]. Temperaments
## (shy, curious, friendly, calm) are profiles in [code]data/fauna/[/code].

@export_group("Threats")
## Within this distance a fast-approaching player makes it flee (0 = never flees).
@export_range(0.0, 100.0, 0.5, "suffix:m") var flee_radius: float = 0.0
## Closing speed of the player that counts as a threat.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var flee_trigger_speed: float = 0.0
## Within this distance it flees whatever the player's speed (0 = never).
@export_range(0.0, 50.0, 0.5, "suffix:m") var startle_radius: float = 0.0
## It keeps fleeing until the player is this far.
@export_range(0.0, 200.0, 0.5, "suffix:m") var safe_distance: float = 0.0

@export_group("Curiosity")
## Within this distance it may walk over to look at the player (0 = never).
@export_range(0.0, 100.0, 0.5, "suffix:m") var approach_radius: float = 0.0
## Where it stops to look at the player.
@export_range(0.5, 50.0, 0.5, "suffix:m") var approach_stop_distance: float = 3.0
## Chance per decision to approach when the player is within range.
@export_range(0.0, 1.0, 0.01) var approach_chance: float = 0.0
## Seconds it watches the player before going back to its own business.
@export_range(0.0, 60.0, 0.5, "suffix:s") var watch_time: float = 6.0

@export_group("Idle time")
## Relative weights of wandering, grazing and resting when nothing else goes on.
@export var idle_weights: Vector3 = Vector3(0.5, 0.35, 0.15)
## Seconds a grazing bout lasts (uniform in [x, y]).
@export var graze_time: Vector2 = Vector2(4.0, 10.0)
## Seconds a rest lasts (uniform in [x, y]).
@export var rest_time: Vector2 = Vector2(10.0, 20.0)
## Wander steps (targets) before the next idle decision.
@export_range(1, 10) var wander_steps: int = 2

@export_group("Following")
## Distance it keeps behind the player it follows.
@export_range(0.5, 20.0, 0.5, "suffix:m") var follow_distance: float = 2.5


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if flee_radius > 0.0 and safe_distance <= flee_radius:
		errors.append("safe_distance must be > flee_radius")
	if startle_radius > flee_radius:
		errors.append("startle_radius must be <= flee_radius")
	if approach_radius > 0.0 and approach_stop_distance >= approach_radius:
		errors.append("approach_stop_distance must be < approach_radius")
	if idle_weights.x < 0.0 or idle_weights.y < 0.0 or idle_weights.z < 0.0:
		errors.append("idle_weights must be >= 0")
	if idle_weights.x + idle_weights.y + idle_weights.z <= 0.0:
		errors.append("idle_weights must not all be 0")
	if graze_time.x > graze_time.y or rest_time.x > rest_time.y:
		errors.append("time ranges must satisfy min <= max")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
