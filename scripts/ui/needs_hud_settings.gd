class_name NeedsHudSettings
extends Resource
## Look and timing of the needs HUD. Values live in [code]data/ui/needs_hud.tres[/code].

## Side of each meter.
@export_range(16.0, 256.0, 1.0, "suffix:px") var meter_size: float = 0.0
## Ring thickness.
@export_range(1.0, 32.0, 0.5, "suffix:px") var ring_width: float = 0.0
## Colour of the empty part of the ring and the disc behind the icon.
@export var backdrop_color: Color = Color.BLACK
## Icon colour.
@export var icon_color: Color = Color.WHITE
## A meter at or above this fraction counts as full.
@export_range(0.0, 1.0, 0.01) var full_fraction: float = 0.0
## Seconds a full meter stays visible before fading out.
@export_range(0.0, 30.0, 0.1, "suffix:s") var full_hold: float = 0.0
## Opacity change per second (fading in and out).
@export_range(0.01, 20.0, 0.01, "suffix:1/s") var fade_per_second: float = 0.0
## How much a critical meter dims at the bottom of its pulse (0 = no pulse).
@export_range(0.0, 1.0, 0.01) var pulse_amount: float = 0.0
## Pulses per second of a critical meter.
@export_range(0.05, 5.0, 0.05, "suffix:Hz") var pulse_hz: float = 0.0
## How long a meter flashes when its need blocks an action (seconds; ADR-012).
@export_range(0.1, 3.0, 0.05, "suffix:s") var flash_seconds: float = 0.1
## How much a flashing meter dims at the bottom of each flash (0 = no flash).
@export_range(0.0, 1.0, 0.01) var flash_amount: float = 0.0
## Flashes in [member flash_seconds].
@export_range(1, 5, 1) var flash_count: int = 1
