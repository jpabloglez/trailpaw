class_name NeedCueSettings
extends Resource
## How the animal shows its need cues (ADR-012): panting, a hungry tummy and shivering. Values
## live in [code]data/needs/need_cues.tres[/code]; [NeedCues] plays them.

## Breathy panting loop (cue [code]&"pant"[/code]).
@export var pant_stream: AudioStream
## Volume of the panting at full strength.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var pant_volume_db: float = 0.0
## Breaths per second shown on the body while panting.
@export_range(0.5, 6.0, 0.1, "suffix:Hz") var pant_hz: float = 1.0
## How much the chest rises with each pant (fraction of the model's height).
@export_range(0.0, 0.1, 0.001) var pant_breath: float = 0.0

@export_group("Hungry")
## Tummy rumble (cue [code]&"growl"[/code]).
@export var growl_stream: AudioStream
## Volume of the rumble.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var growl_volume_db: float = 0.0
## Seconds before the first rumble once hungry.
@export_range(0.0, 60.0, 0.5, "suffix:s") var growl_first: float = 0.0
## Seconds between rumbles, picked at random between these.
@export var growl_every: Vector2 = Vector2(30.0, 30.0)

@export_group("Cold")
## Largest roll of the body while shivering (cue [code]&"shiver"[/code]).
@export_range(0.0, 10.0, 0.1, "suffix:°") var shiver_degrees: float = 0.0
## Shivers per second.
@export_range(1.0, 30.0, 0.5, "suffix:Hz") var shiver_hz: float = 10.0

@export_group("Mix")
## How fast each cue fades in and out (strength per second).
@export_range(0.1, 10.0, 0.1, "suffix:1/s") var ease_per_second: float = 1.0
## Audio bus.
@export var bus: StringName = &"SFX"
## Seed of the rumble timing.
@export var seed_value: int = 0
