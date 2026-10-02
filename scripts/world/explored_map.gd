class_name ExploredMap
extends RefCounted
## The part of the world the player has seen, as a set of square cells in absolute
## coordinates (fog of war for the map), plus the water the player has scented. Saved with the
## game through [method to_dict] / [method from_dict] (plain JSON-friendly values).
## [br][br]
## Budget: [method reveal] checks (2r/cell + 1)² cells — 49 for the defaults — and only
## allocates when a cell is new.

## Format version of [method to_dict].
const VERSION: int = 1

## Side of a cell (m).
var cell_size: float
## Bumped whenever something new is revealed or marked (the map redraws when it changes).
var revision: int = 0

var _cells: Dictionary[Vector2i, bool] = {}
var _water: Array[Vector3] = []
var _max_water: int
var _merge: float


func _init(settings: ExplorationSettings) -> void:
	cell_size = settings.cell_size
	_max_water = settings.max_water_marks
	_merge = settings.water_mark_merge


## Reveals the cells whose centre lies within [param radius] of [param absolute] (X, Z).
## Returns how many were new.
func reveal(absolute: Vector3, radius: float) -> int:
	var centre := cell_of(absolute.x, absolute.z)
	var reach := ceili(radius / cell_size)
	var radius_sq := radius * radius
	var added := 0
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := centre + Vector2i(dx, dz)
			if _cells.has(cell):
				continue
			var cx := (cell.x + 0.5) * cell_size - absolute.x
			var cz := (cell.y + 0.5) * cell_size - absolute.z
			if cx * cx + cz * cz <= radius_sq:
				_cells[cell] = true
				added += 1
	if added > 0:
		revision += 1
	return added


## Whether the absolute point ([param x], [param z]) has been seen.
func is_explored(x: float, z: float) -> bool:
	return _cells.has(cell_of(x, z))


## Cell containing the absolute point ([param x], [param z]).
func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / cell_size), floori(z / cell_size))


## A copy of the explored cells (for a worker thread to read while the game goes on).
func cells_snapshot() -> Dictionary[Vector2i, bool]:
	return _cells.duplicate()


## Number of explored cells.
func cell_count() -> int:
	return _cells.size()


## Remembers scented water at [param absolute]; replaces a mark that is already close by and
## drops the oldest beyond the limit.
func add_water_mark(absolute: Vector3) -> void:
	for i in _water.size():
		if Vector2(_water[i].x - absolute.x, _water[i].z - absolute.z).length() <= _merge:
			_water.remove_at(i)
			break
	_water.append(absolute)
	while _water.size() > _max_water:
		_water.remove_at(0)
	revision += 1


## Scented water marks (absolute), oldest first.
func water_marks() -> Array[Vector3]:
	return _water.duplicate()


## Forgets everything.
func clear() -> void:
	_cells.clear()
	_water.clear()
	revision += 1


## Plain, JSON-friendly copy: cells as a flat [x0, z0, x1, z1, …] list.
func to_dict() -> Dictionary:
	var flat: Array[int] = []
	for cell: Vector2i in _cells:
		flat.append(cell.x)
		flat.append(cell.y)
	var water: Array = []
	for mark in _water:
		water.append([mark.x, mark.y, mark.z])
	return {"version": VERSION, "cell_size": cell_size, "cells": flat, "water": water}


## Replaces the contents with [param data] (from [method to_dict]); cells saved with another
## cell size are dropped rather than misplaced.
func from_dict(data: Dictionary) -> void:
	clear()
	if not is_equal_approx(float(data.get("cell_size", cell_size)), cell_size):
		return
	var flat: Array = data.get("cells", [])
	for i in range(0, flat.size() - 1, 2):
		_cells[Vector2i(int(flat[i]), int(flat[i + 1]))] = true
	for entry: Variant in data.get("water", []):
		if entry is Array and (entry as Array).size() == 3:
			var at: Array = entry
			_water.append(Vector3(float(at[0]), float(at[1]), float(at[2])))
	revision += 1
