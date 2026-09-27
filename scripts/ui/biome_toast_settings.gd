class_name BiomeToastSettings
extends Resource
## Timing of the biome-name toast. Values live in [code]data/ui/biome_toast.tres[/code].

## Seconds to fade in.
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_in: float = 0.0
## Seconds fully visible.
@export_range(0.0, 20.0, 0.05, "suffix:s") var hold: float = 0.0
## Seconds to fade out.
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_out: float = 0.0


## Total time the toast is on screen.
func total() -> float:
	return fade_in + hold + fade_out
