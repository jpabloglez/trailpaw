class_name AutosaveSettings
extends Resource
## When the game saves itself. Values live in [code]data/save/autosave.tres[/code].

## Real seconds between periodic saves.
@export_range(10.0, 3600.0, 1.0, "suffix:s") var interval_seconds: float = 300.0
## A biome change saves only if the last save is at least this old (real seconds).
@export_range(0.0, 600.0, 1.0, "suffix:s") var biome_min_gap_seconds: float = 30.0
