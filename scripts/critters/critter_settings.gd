class_name CritterSettings
extends Resource
## Population and simulation of the critter layer. Values live in
## [code]data/critters/system.tres[/code].

## Most critters alive at once (all kinds).
@export_range(1, 512) var max_total: int = 120
## Decision ticks per second (hops are animated every frame).
@export_range(1.0, 60.0, 1.0, "suffix:Hz") var sim_hz: float = 30.0
## Beyond this distance from the player critters decide every 3rd tick (m).
@export_range(5.0, 300.0, 1.0, "suffix:m") var far_distance: float = 60.0
