class_name RestSettings
extends Resource
## How resting recovers energy. Values live in [code]data/interaction/rest.tres[/code].

## Energy recovered per second resting in the open (on top of the idle recovery).
@export_range(0.0, 50.0, 0.01, "suffix:/s") var energy_per_second: float = 0.0
## Multiplier in a tree's shade.
@export_range(1.0, 10.0, 0.1) var shade_multiplier: float = 1.0
## Multiplier by a den.
@export_range(1.0, 10.0, 0.1) var den_multiplier: float = 1.0
