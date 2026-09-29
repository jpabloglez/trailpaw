class_name ChunkDeltaStore
extends RefCounted
## What the player changed in the world, per chunk: depleted resources and when they regrow.
## Owned by [WorldStreamer] and shared by all its chunks, so a bush eaten bare stays bare when
## its chunk unloads and loads again. Only the changes are stored (a delta over the seeded
## world), keyed by absolute chunk coordinate, resource id and instance index, so saves stay
## small ([method to_dict] / [method from_dict], Phase 10).
## [br][br]
## Budget: dictionary lookups; entries are removed as soon as they regrow.

## Schema version of [method to_dict].
const VERSION: int = 1

## coord → {resource id → {instance index → game minute it regrows at}}.
var _entries: Dictionary[Vector2i, Dictionary] = {}


## Marks instance [param index] of [param id] in chunk [param coord] depleted until
## [param regrow_at] (game minutes).
func deplete(coord: Vector2i, id: StringName, index: int, regrow_at: float) -> void:
	if not _entries.has(coord):
		_entries[coord] = {}
	var chunk: Dictionary = _entries[coord]
	if not chunk.has(id):
		chunk[id] = {}
	(chunk[id] as Dictionary)[index] = regrow_at


## Whether that instance is depleted at game minute [param now].
func is_depleted(coord: Vector2i, id: StringName, index: int, now: float) -> bool:
	var chunk: Dictionary = _entries.get(coord, {})
	var ids: Dictionary = chunk.get(id, {})
	return ids.has(index) and now < float(ids[index])


## Depleted instances of chunk [param coord]: {id → {index → regrow_at}} (do not modify).
func entries_for(coord: Vector2i) -> Dictionary:
	return _entries.get(coord, {})


## Removes (and returns as [[id, index], …]) the entries of [param coord] regrown at
## [param now].
func take_regrown(coord: Vector2i, now: float) -> Array:
	var regrown: Array = []
	var chunk: Dictionary = _entries.get(coord, {})
	for id: StringName in chunk.keys():
		var ids: Dictionary = chunk[id]
		for index: int in ids.keys():
			if now >= float(ids[index]):
				ids.erase(index)
				regrown.append([id, index])
		if ids.is_empty():
			chunk.erase(id)
	if chunk.is_empty():
		_entries.erase(coord)
	return regrown


## Removes every entry regrown at [param now], in all chunks.
func prune(now: float) -> void:
	for coord: Vector2i in _entries.keys():
		take_regrown(coord, now)


## Number of depleted instances stored.
func size() -> int:
	var count := 0
	for coord: Vector2i in _entries:
		for id: StringName in _entries[coord]:
			count += (_entries[coord][id] as Dictionary).size()
	return count


## Plain, JSON-friendly copy: {version, chunks: [[x, y, id, index, regrow_at], …]}.
func to_dict() -> Dictionary:
	var rows: Array = []
	for coord: Vector2i in _entries:
		for id: StringName in _entries[coord]:
			var ids: Dictionary = _entries[coord][id]
			for index: int in ids:
				rows.append([coord.x, coord.y, String(id), index, float(ids[index])])
	return {"version": VERSION, "chunks": rows}


## Replaces the contents with [param data] from [method to_dict].
func from_dict(data: Dictionary) -> void:
	_entries.clear()
	for row: Array in data.get("chunks", []):
		deplete(Vector2i(int(row[0]), int(row[1])), StringName(row[2]), int(row[3]), float(row[4]))
