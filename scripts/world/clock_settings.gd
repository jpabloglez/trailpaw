class_name ClockSettings
extends Resource
## Pace of the game clock ([code]GameState.game_minutes[/code]). Values live in
## [code]data/world/clock.tres[/code]; Phase 9 (day/night) builds on it.

## Game minutes per real second at normal pace.
@export_range(0.01, 60.0, 0.01, "suffix:min/s") var minutes_per_second: float = 0.0
## Time of day the session starts at (minutes after midnight).
@export_range(0.0, 1439.0, 1.0, "suffix:min") var start_minutes: float = 0.0
## Clock multiplier while the animal rests.
@export_range(1.0, 100.0, 0.5) var rest_scale: float = 1.0
