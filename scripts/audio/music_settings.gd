class_name MusicSettings
extends Resource
## How the music plays ([MusicDirector], Phase 20): the themes, the moments of the day, and
## the spells of music between silences. Values live in [code]data/audio/music.tres[/code].

## The biomes' themes (a biome without one has no music).
@export var themes: Array[MusicTheme] = []
## The title screen's theme and moment.
@export var title_biome: StringName = &"meadow"
@export var title_moment: StringName = &"day"
## Bus the music plays on.
@export var bus: StringName = &"Music"

@export_group("Moments")
## Hours where dawn, day, dusk and night begin (game hours, 0…24).
@export var dawn_from: float = 5.0
@export var day_from: float = 8.0
@export var dusk_from: float = 18.0
@export var night_from: float = 21.0

@export_group("Spells")
## Silence between two themes (min, max seconds; "sometimes").
@export var pauses: Vector2 = Vector2(120.0, 300.0)
## The first theme of a game comes within this (min, max seconds).
@export var first_spell: Vector2 = Vector2(20.0, 60.0)
## "Often" scales the pauses by this.
@export_range(0.05, 1.0, 0.05) var often_factor: float = 0.4
## The title theme comes back after this silence (s).
@export_range(0.0, 120.0, 1.0, "suffix:s") var title_pause: float = 20.0
## After a theme fades out for a change, the next may start after this (min, max seconds).
@export var change_gap: Vector2 = Vector2(6.0, 12.0)
## Fades (s).
@export_range(0.1, 30.0, 0.1, "suffix:s") var fade_in: float = 4.0
@export_range(0.1, 30.0, 0.1, "suffix:s") var fade_out: float = 6.0
## A new biome counts once the fox has been in it this long (s): no fading in and out along
## a border.
@export_range(0.0, 60.0, 0.5, "suffix:s") var settle_seconds: float = 8.0
## Rain heavier than this (the [Weather]'s [code]rain_here[/code], 0…1) silences the music.
@export_range(0.0, 1.0, 0.05) var rain_threshold: float = 0.3


## The theme of biome [param id], or null.
func theme_for(id: StringName) -> MusicTheme:
	for theme in themes:
		if theme.biome == id:
			return theme
	return null


## The moment of the day at [param hour] (0…24): [code]&"dawn"[/code], [code]&"day"[/code],
## [code]&"dusk"[/code] or [code]&"night"[/code].
func moment_of(hour: float) -> StringName:
	if hour >= night_from or hour < dawn_from:
		return &"night"
	if hour < day_from:
		return &"dawn"
	if hour < dusk_from:
		return &"day"
	return &"dusk"


## Problems that would break the music (empty when valid).
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for theme in themes:
		if theme.day == null:
			errors.append("theme %s has no day stream" % theme.biome)
	if theme_for(title_biome) == null:
		errors.append("no title theme %s" % title_biome)
	if not (dawn_from < day_from and day_from < dusk_from and dusk_from < night_from):
		errors.append("moments must be in order")
	if pauses.x > pauses.y or first_spell.x > first_spell.y or change_gap.x > change_gap.y:
		errors.append("ranges must be ordered")
	return errors
