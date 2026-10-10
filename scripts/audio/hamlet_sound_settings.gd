class_name HamletSoundSettings
extends Resource
## The sounds of the hamlets ([HamletSounds]). Values live in
## [code]data/audio/hamlet_sounds.tres[/code].

## Hens about the yard (a seamless loop), by day.
@export var yard: AudioStream
## The rooster at dawn.
@export var rooster: AudioStream
## Calls from the pen, one picked at random each time (sheep, cow, pig).
@export var pen_calls: Array[AudioStream] = []
## A villager shooing the fox (hand claps).
@export var shoo: AudioStream
## Game hour the rooster crows at (each hamlet, once a day).
@export_range(0.0, 24.0, 0.05) var rooster_hour: float = 6.0
## Hours the yard is alive (hens out) and the pen calls (from, to).
@export var day: Vector2 = Vector2(6.0, 20.5)
## Seconds between pen calls (min, max).
@export var call_seconds: Vector2 = Vector2(12.0, 35.0)
## Volumes (dB) and how far each carries (unit size, max distance; m).
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var yard_db: float = -12.0
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var rooster_db: float = -4.0
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var call_db: float = -8.0
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var shoo_db: float = -4.0
@export var yard_reach: Vector2 = Vector2(6.0, 70.0)
@export var call_reach: Vector2 = Vector2(8.0, 120.0)
