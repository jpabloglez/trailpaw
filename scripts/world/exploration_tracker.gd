class_name ExplorationTracker
extends Node
## Remembers where the player has been for the map: every [member ExplorationSettings.interval]
## seconds it reveals the cells around [member target] (absolute position, so floating-origin
## rebases do not matter), and it keeps the water the [member sniffer] scents.
## [br][br]
## Budget: one [method ExploredMap.reveal] per interval (49 cell checks by default); nothing
## else per frame.

## How the area is remembered.
@export var settings: ExplorationSettings
## Whose surroundings are revealed (the player animal).
@export var target: Node3D
## Its sniffer: scented water becomes a map mark (optional).
@export var sniffer: Sniffer

## What has been explored.
var explored: ExploredMap

var _since: float = 0.0


func _ready() -> void:
	explored = ExploredMap.new(settings)
	if sniffer != null:
		sniffer.water_scented.connect(explored.add_water_mark)


func _process(delta: float) -> void:
	_since += delta
	if _since >= settings.interval:
		_since = 0.0
		reveal_now()


## Reveals around the target now. Returns how many cells were new.
func reveal_now() -> int:
	if target == null:
		return 0
	var at := GameState.absolute_position(target.global_position)
	return explored.reveal(at, settings.reveal_radius)
