class_name InteractorSettings
extends Resource
## Reach and scoring of the [Interactor]. Values live in
## [code]data/interaction/interactor.tres[/code].

## How far in front of the body the probe sphere travels.
@export_range(0.0, 5.0, 0.05, "suffix:m") var reach_distance: float = 0.0
## Radius of the probe sphere.
@export_range(0.05, 3.0, 0.05, "suffix:m") var reach_radius: float = 0.0
## Height of the probe above the body origin (the paws).
@export_range(0.0, 2.0, 0.05, "suffix:m") var probe_height: float = 0.0
## Targets further than this (horizontally) are ignored.
@export_range(0.1, 10.0, 0.05, "suffix:m") var max_distance: float = 0.0
## Targets more than this off the facing direction are ignored.
@export_range(0.0, 180.0, 1.0, "suffix:°") var max_angle_degrees: float = 0.0
## Distance vs facing in the score (0 = only facing, 1 = only distance).
@export_range(0.0, 1.0, 0.01) var distance_weight: float = 0.0
