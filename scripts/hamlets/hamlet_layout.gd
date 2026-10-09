class_name HamletLayout
extends RefCounted
## One hamlet: where it is (absolute) and the pieces it is built from. Made by [HamletPlan].

## World cell it belongs to.
var cell: Vector2i
## The well at its heart (absolute; [code]y[/code] is the ground there).
var centre: Vector3
## Biome it stands in.
var biome: StringName
## Pieces: their ids, absolute positions (ground height in [code]y[/code]), yaws (rad) and
## footprint radii (m), in build order (the well first, then houses, the stable and pen, props).
var ids: Array[StringName] = []
var positions := PackedVector3Array()
var yaws := PackedFloat32Array()
var radii := PackedFloat32Array()
## Where the stable's pen is (absolute) and its half size (m): farm animals live inside.
var pen := Vector3.INF
var pen_half: float = 0.0


## Number of pieces.
func size() -> int:
	return ids.size()


## Appends a piece.
func add(id: StringName, at: Vector3, yaw: float, radius: float) -> void:
	ids.append(id)
	positions.append(at)
	yaws.append(yaw)
	radii.append(radius)


## Whether a circle of [param radius] at absolute ([param x], [param z]) overlaps any piece.
func overlaps(x: float, z: float, radius: float) -> bool:
	for i in ids.size():
		var dx := positions[i].x - x
		var dz := positions[i].z - z
		var reach := radii[i] + radius
		if dx * dx + dz * dz < reach * reach:
			return true
	return false
