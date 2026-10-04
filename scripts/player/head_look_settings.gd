class_name HeadLookSettings
extends Resource
## What the player's head turns to and how far. Values live in
## [code]data/player/head_look.tres[/code].

## Animals within this distance are looked at when nothing is targeted (m).
@export_range(0.0, 50.0, 0.5, "suffix:m") var animal_range: float = 0.0
## Total yaw range (degrees; half each way).
@export_range(0.0, 180.0, 1.0, "suffix:°") var yaw_range: float = 120.0
## Total pitch range (degrees; half each way).
@export_range(0.0, 180.0, 1.0, "suffix:°") var pitch_range: float = 60.0
## How fast the gaze follows its target (1/s).
@export_range(0.1, 60.0, 0.1, "suffix:1/s") var smoothing: float = 6.0
## Above this speed (× the species' trot speed) the head is left to the animation.
@export_range(0.0, 3.0, 0.05) var max_speed_factor: float = 1.0
## Where the head rests when there is nothing to look at: this far ahead (m).
@export_range(0.5, 20.0, 0.5, "suffix:m") var ahead: float = 4.0
