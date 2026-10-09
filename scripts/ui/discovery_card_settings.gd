class_name DiscoveryCardSettings
extends Resource
## Timings and look of the new-animal card ([DiscoveryCard]). Values live in
## [code]data/ui/discovery_card.tres[/code].

## Seconds to slide in, to stay, and to slide out.
@export_range(0.05, 3.0, 0.05, "suffix:s") var slide_in: float = 0.45
@export_range(0.5, 20.0, 0.1, "suffix:s") var hold: float = 4.0
@export_range(0.05, 3.0, 0.05, "suffix:s") var slide_out: float = 0.4
## Side of the turning figure (px) and its turning speed (rad/s).
@export_range(64, 512, 8) var portrait_size: int = 150
@export_range(0.0, 6.0, 0.1) var spin: float = 1.2
## Distance from the top and right edges of the screen (px).
@export var margin: Vector2 = Vector2(24.0, 140.0)
## Chime volume (dB) on the SFX bus.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var chime_volume_db: float = -8.0
