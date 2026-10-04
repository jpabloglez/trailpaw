class_name FootPlantSettings
extends Resource
## How the paws follow uneven ground. Values live in [code]data/player/foot_plant.tres[/code].

## Highest a paw is lifted onto a bump or step (m).
@export_range(0.0, 1.0, 0.01, "suffix:m") var max_raise: float = 0.0
## Lowest a paw reaches down into a dip (m).
@export_range(0.0, 1.0, 0.01, "suffix:m") var max_drop: float = 0.0
## Ground probe: start above the animated paw and length below it (m).
@export_range(0.05, 2.0, 0.01, "suffix:m") var probe_up: float = 0.4
@export_range(0.05, 2.0, 0.01, "suffix:m") var probe_down: float = 0.4
## Above this speed (× the species' trot speed) the feet are left to the animation.
@export_range(0.0, 3.0, 0.05) var max_speed_factor: float = 1.0
## How fast offsets and the influence follow their targets (1/s).
@export_range(0.1, 60.0, 0.1, "suffix:1/s") var smoothing: float = 12.0
