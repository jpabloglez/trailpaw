class_name AmbienceSettings
extends Resource
## The ambience mix: layers and cross-fade time. Values live in
## [code]data/audio/ambience.tres[/code].

## Looping layers.
@export var layers: Array[AmbienceLayer] = []
## Seconds a full cross-fade takes (biome, day/night and weather changes).
@export_range(0.1, 30.0, 0.1, "suffix:s") var fade_seconds: float = 3.0
## Audio bus of every layer.
@export var bus: StringName = &"Ambience"
