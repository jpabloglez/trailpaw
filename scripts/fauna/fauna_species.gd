class_name FaunaSpecies
extends Resource
## A wild species: its animal (model, gaits, animations), temperament and how it lives. Lives
## under [code]data/fauna/[/code]; biomes list which species appear where (Phase 8).

## How an animal relates to the player.
enum Temperament { SHY, CURIOUS, FRIENDLY, CALM }

## Stable identifier (events, saves).
@export var id: StringName = &""
## Name shown to the player.
@export var display_name: String = ""
## Model, gaits and animations.
@export var animal: AnimalSpecies
## How it relates to the player.
@export var temperament: Temperament = Temperament.CALM
## Reactions and time use (usually the temperament's profile in
## [code]data/fauna/temperaments/[/code]).
@export var profile: FaunaProfile
## Animals per group (uniform in [x, y]).
@export var herd_size: Vector2i = Vector2i(1, 1)
## How far from home it wanders (m).
@export_range(1.0, 200.0, 0.5, "suffix:m") var wander_radius: float = 12.0
## Seconds a friendly animal follows after playing.
@export_range(0.0, 600.0, 1.0, "suffix:s") var follow_seconds: float = 75.0

@export_group("Voice")
## Call (a recorded clip), or none.
@export var voice: AudioStream
## A synthesised call when there is no recording ([code]&"yip"[/code], see [SynthSounds]).
@export var voice_synth: StringName = &""
## Seconds between idle calls, uniform in [x, y] (0 = only calls when greeted).
@export var call_interval: Vector2 = Vector2.ZERO


## The call to play, or null for a quiet species.
func call_stream() -> AudioStream:
	if voice != null:
		return voice
	if voice_synth == &"yip":
		return SynthSounds.yip()
	return null


## Whether it can be greeted (all can, unless the temperament keeps it away: shy animals only
## while they are not fleeing, which the social interaction checks).
func can_be_greeted() -> bool:
	return true


## Whether it plays after a greeting.
func can_play() -> bool:
	return temperament == Temperament.FRIENDLY or temperament == Temperament.CURIOUS


## Whether it follows the player after playing.
func follows_after_play() -> bool:
	return temperament == Temperament.FRIENDLY


## Returns human-readable problems with the data; empty when valid.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if animal == null:
		errors.append("animal must be set")
	elif not animal.is_valid():
		errors.append("animal: %s" % ", ".join(animal.get_validation_errors()))
	if profile == null:
		errors.append("profile must be set")
	elif not profile.is_valid():
		errors.append("profile: %s" % ", ".join(profile.get_validation_errors()))
	if herd_size.x < 1 or herd_size.x > herd_size.y:
		errors.append("herd_size must satisfy 1 <= min <= max")
	return errors


## Returns [code]true[/code] when [method get_validation_errors] finds no problems.
func is_valid() -> bool:
	return get_validation_errors().is_empty()
