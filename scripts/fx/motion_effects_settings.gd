class_name MotionEffectsSettings
extends Resource
## Dust and splash effects of the player's movement. Values live in
## [code]data/fx/motion_effects.tres[/code].

## Dust from footsteps only at or above this speed (× the species' trot speed).
@export_range(0.0, 3.0, 0.05) var dust_speed_factor: float = 0.9
## A landing raises a puff (and a splash in water) when falling at least this fast (m/s).
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var landing_speed: float = 3.0
## Particles per footstep puff, landing puff and splash.
@export_range(1, 64) var step_amount: int = 6
@export_range(1, 128) var landing_amount: int = 16
@export_range(1, 128) var splash_amount: int = 14
## Seconds a puff or splash lasts.
@export_range(0.1, 5.0, 0.05, "suffix:s") var lifetime: float = 0.8
## Dust tint mixed into the biome's ground colour (lighter, dusty).
@export var dust_tint: Color = Color(0.9, 0.85, 0.75, 0.55)
## Splash colour.
@export var splash_color: Color = Color(0.85, 0.93, 1.0, 0.7)
## Effects alive at once (the oldest is reused).
@export_range(1, 16) var pool_size: int = 4
