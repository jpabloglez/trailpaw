class_name ExplorationSettings
extends Resource
## How the explored area is remembered (fog of war for the map). Values live in
## [code]data/world/exploration.tres[/code].

## Side of an explored cell (m).
@export_range(4.0, 256.0, 1.0, "suffix:m") var cell_size: float = 32.0
## Cells whose centre lies within this distance of the animal are revealed.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var reveal_radius: float = 96.0
## Seconds between reveals.
@export_range(0.05, 10.0, 0.05, "suffix:s") var interval: float = 0.5
## Most scented-water marks kept (the oldest are dropped).
@export_range(1, 512) var max_water_marks: int = 64
## A new water mark this close to an old one replaces it.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var water_mark_merge: float = 60.0
