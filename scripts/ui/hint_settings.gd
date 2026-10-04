class_name HintSettings
extends Resource
## The onboarding hints: their short texts and when they show. Values live in
## [code]data/ui/hints.tres[/code]. Texts may use [code]{move}[/code], [code]{sprint}[/code],
## [code]{sniff}[/code], [code]{interact}[/code], [code]{map}[/code], [code]{rest}[/code] (the
## player's keys) and [code]{hold_sprint}[/code] / [code]{hold_rest}[/code] ("Hold" or "Press",
## following the hold-or-toggle setting).

## Hint id → text, in the order they are taught.
@export var texts: Dictionary[StringName, String] = {}
## Seconds after the animal lands before the first hint.
@export_range(0.0, 30.0, 0.5, "suffix:s") var first_delay: float = 1.5
## Metres walked that count as "moved".
@export_range(0.5, 50.0, 0.5, "suffix:m") var move_distance: float = 6.0
## Seconds of running that count as "ran".
@export_range(0.1, 10.0, 0.1, "suffix:s") var run_seconds: float = 1.5
## Sniffing is suggested when thirst or hunger drops below this (or after
## [member sniff_after] seconds).
@export_range(0.0, 100.0, 1.0) var sniff_below: float = 75.0
@export_range(0.0, 600.0, 5.0, "suffix:s") var sniff_after: float = 90.0
## Eating is suggested when hunger drops below this.
@export_range(0.0, 100.0, 1.0) var eat_below: float = 70.0
## The map is suggested once some water has been scented, or after this long.
@export_range(0.0, 1200.0, 10.0, "suffix:s") var map_after: float = 240.0
## Resting is suggested when energy drops below this.
@export_range(0.0, 100.0, 1.0) var rest_below: float = 50.0
## Fade in/out speed (opacity per second).
@export_range(0.5, 20.0, 0.5) var fade_per_second: float = 3.0
