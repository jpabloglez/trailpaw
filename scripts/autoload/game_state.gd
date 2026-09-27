## Session-wide game state: world seed, distance travelled, current biome, elapsed time
## and pause state.
##
## Fields are added by the phase that needs them (see [code]docs/ARCHITECTURE.md[/code] §2).
## [br][br]
## Autoload name: [code]GameState[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node

## Seed for all procedural world generation. Set before the world starts streaming.
var world_seed: int = 0
