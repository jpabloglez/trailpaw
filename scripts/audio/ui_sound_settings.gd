class_name UiSoundSettings
extends Resource
## Interface sounds. Values live in [code]data/audio/ui_sounds.tres[/code].

## Soft pluck when an interaction prompt appears.
@export var prompt: AudioStream
## Gentle chime when a need becomes critical.
@export var need_critical: AudioStream
## Soft whoosh when sniffing.
@export var sniff: AudioStream
## Volume of every interface sound.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var volume_db: float = 0.0
## Audio bus.
@export var bus: StringName = &"SFX"
