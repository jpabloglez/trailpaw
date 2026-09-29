class_name InteractionDefinition
extends Resource
## Data for one kind of interaction: what it is, how it is triggered and what it does to the
## needs. Lives under [code]data/interactions/[/code] (ARCHITECTURE §6).
##
## [constant Mode] ONCE plays for [member duration] seconds and applies [member need_effects]
## (need id → amount) a single time at the end; HOLD applies them as rates per second while the
## player holds the interact action. A source with [member regrowth_minutes] > 0 is depleted by
## a completed ONCE interaction and comes back after that many game minutes.

## What the interaction is.
enum Type { EAT, DRINK, COOL_OFF, REST, SOCIAL }
## How it is triggered.
enum Mode { ONCE, HOLD }

## Stable identifier (e.g. [code]&"berries"[/code]).
@export var id: StringName = &""
## What the interaction is.
@export var type: Type = Type.EAT
## Prompt shown next to the key, e.g. "Eat berries".
@export var prompt: String = ""
## Press once or hold.
@export var mode: Mode = Mode.ONCE
## Need id → amount (ONCE) or amount per second (HOLD).
@export var need_effects: Dictionary[StringName, float] = {}
## Logical animation played ([constant AnimationController.ACTIONS]).
@export var animation: StringName = &""
## Seconds a ONCE interaction takes.
@export_range(0.0, 30.0, 0.05, "suffix:s") var duration: float = 0.0
## Kind of food, checked against [member AnimalSpecies.diet] (empty for non-food).
@export var food_kind: StringName = &""
## Game minutes until a depleted source is back (0 = never depletes).
@export_range(0.0, 10000.0, 1.0, "suffix:min") var regrowth_minutes: float = 0.0


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if prompt.strip_edges().is_empty():
		errors.append("prompt must not be empty")
	if not AnimationController.ACTIONS.has(animation):
		errors.append("animation must be one of %s" % [AnimationController.ACTIONS])
	if mode == Mode.ONCE and duration <= 0.0:
		errors.append("a ONCE interaction needs duration > 0")
	if type == Type.EAT and food_kind == &"":
		errors.append("an EAT interaction needs a food_kind")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
