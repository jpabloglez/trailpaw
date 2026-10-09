class_name AnimalJournal
extends RefCounted
## The animals the player has met: for each, when (game minutes) and where (biome) it was first
## seen. Saved through [method to_dict] / [method from_dict].

## Format version of [method to_dict].
const VERSION: int = 1

var _seen: Dictionary[StringName, Dictionary] = {}


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


## Forgets everything.
func clear() -> void:
	_seen.clear()


## Plain, JSON-friendly copy.
func to_dict() -> Dictionary:
	var seen := {}
	for id: StringName in _seen:
		seen[String(id)] = _seen[id].duplicate()
	return {"version": VERSION, "seen": seen}


## Replaces the contents with [param data] (from [method to_dict]; empty is an empty journal).
func from_dict(data: Dictionary) -> void:
	clear()
	var seen: Dictionary = data.get("seen", {})
	for id: String in seen:
		var record: Dictionary = seen[id] if seen[id] is Dictionary else {}
		_seen[StringName(id)] = {
			"minutes": float(record.get("minutes", 0.0)), "biome": str(record.get("biome", ""))
		}
