class_name IslandTreasure
extends RefCounted
## One island treasure: where it is (absolute) and what it is. Made by [IslandPlan].

## World cell it belongs to.
var cell: Vector2i
## The island's top, where the treasure stands (absolute; [code]y[/code] is the ground).
var centre: Vector3
## What it is ([enum IslandPlan.Treasure]).
var kind: int = 0
## Mean distance from the top to the water: the island's rough radius (m).
var radius: float = 0.0
## Seed for its looks (flower layout, log heap…).
var seed: int = 0


## Stable key of the treasure for saves ("x,y" of its cell).
func key() -> String:
	return "%d,%d" % [cell.x, cell.y]
