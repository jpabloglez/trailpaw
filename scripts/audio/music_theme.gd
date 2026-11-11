class_name MusicTheme
extends Resource
## One biome's music (Phase 20): the same theme in its four moments of the day, composed and
## mastered outside the project (ADR-011). A missing moment plays the day's.

## Biome it belongs to.
@export var biome: StringName = &""
## The theme by day, at dawn, at dusk and at night.
@export var day: AudioStream
@export var dawn: AudioStream
@export var dusk: AudioStream
@export var night: AudioStream
## Level trim of this theme (dB), to balance it against the others.
@export_range(-24.0, 6.0, 0.5, "suffix:dB") var volume_db: float = 0.0


## The stream of [param moment] ([code]&"day"[/code], [code]&"dawn"[/code],
## [code]&"dusk"[/code] or [code]&"night"[/code]); the day's when that moment has none.
func stream_for(moment: StringName) -> AudioStream:
	var found: AudioStream = get(moment) if moment in [&"dawn", &"dusk", &"night"] else null
	return found if found != null else day
