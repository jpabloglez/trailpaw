class_name AnimalJournal
extends RefCounted
## The animals the player has met: for each, when (game minutes) and where (biome) it was first
## seen; and the biomes visited (the atlas, Phase 16b): when and where (absolute X, Z) each was
## first entered. Saved through [method to_dict] / [method from_dict].

## Format version of [method to_dict] (2 adds the biomes; version 1 loads without them).
const VERSION: int = 2

var _seen: Dictionary[StringName, Dictionary] = {}
var _biomes: Dictionary[StringName, Dictionary] = {}


## Records [param id] as seen at [param game_minutes] in [param biome]. True only the first
## time (later sightings change nothing).
func discover(id: StringName, game_minutes: float, biome: StringName) -> bool:
	if _seen.has(id):
		return false
	_seen[id] = {"minutes": game_minutes, "biome": String(biome)}
	return true


## Whether [param id] has been seen.
func is_seen(id: StringName) -> bool:
	return _seen.has(id)


## How many animals have been seen.
func seen_count() -> int:
	return _seen.size()


## Biome where [param id] was first seen (empty if never).
func first_biome(id: StringName) -> StringName:
	return StringName(str(_seen.get(id, {}).get("biome", "")))


## Records biome [param id] as visited at [param game_minutes], first entered at
## [param absolute]. True only the first time.
func visit_biome(id: StringName, game_minutes: float, absolute: Vector3) -> bool:
	if _biomes.has(id):
		return false
	_biomes[id] = {"minutes": game_minutes, "x": absolute.x, "z": absolute.z}
	return true


## Whether biome [param id] has been visited.
func has_visited(id: StringName) -> bool:
	return _biomes.has(id)


## How many biomes have been visited.
func visited_count() -> int:
	return _biomes.size()


## Game minutes of the first visit to biome [param id] (−1 if never).
func first_visit(id: StringName) -> float:
	return float(_biomes.get(id, {}).get("minutes", -1.0))


## Forgets everything.
func clear() -> void:
	_seen.clear()
	_biomes.clear()


## Plain, JSON-friendly copy.
func to_dict() -> Dictionary:
	var seen := {}
	for id: StringName in _seen:
		seen[String(id)] = _seen[id].duplicate()
	var biomes := {}
	for id: StringName in _biomes:
		biomes[String(id)] = _biomes[id].duplicate()
	return {"version": VERSION, "seen": seen, "biomes": biomes}


## Replaces the contents with [param data] (from [method to_dict]; empty is an empty journal).
func from_dict(data: Dictionary) -> void:
	clear()
	var seen: Dictionary = data.get("seen", {})
	for id: String in seen:
		var record: Dictionary = seen[id] if seen[id] is Dictionary else {}
		_seen[StringName(id)] = {
			"minutes": float(record.get("minutes", 0.0)), "biome": str(record.get("biome", ""))
		}
	var biomes: Dictionary = data.get("biomes", {})  # absent before version 2
	for id: String in biomes:
		var visit: Dictionary = biomes[id] if biomes[id] is Dictionary else {}
		_biomes[StringName(id)] = {
			"minutes": float(visit.get("minutes", 0.0)),
			"x": float(visit.get("x", 0.0)),
			"z": float(visit.get("z", 0.0)),
		}
