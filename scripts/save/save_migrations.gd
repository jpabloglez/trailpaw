class_name SaveMigrations
extends RefCounted
## Upgrades save dictionaries from older schema versions, one step at a time, to
## [constant SaveData.VERSION].
##
## History:
## [br]- [b]v1[/b] (Phase 10 draft): [code]seed[/code], [code]pos[/code] [x, y, z],
##   [code]needs[/code].
## [br]- [b]v2[/b]: [code]world_seed[/code], [code]player[/code] {position, yaw}, needs, game
##   time, chunk deltas, biome, species, save time.
## [br]- [b]v3[/b] (Phase 10b): [code]explored[/code] — the explored area and scented water.


## [param data] upgraded to the current version, or an empty dictionary when it cannot be
## (no version, or newer than this game knows). [param error] receives the reason.
static func migrate(data: Dictionary, error: Array[String] = []) -> Dictionary:
	if not data.has("version"):
		error.append("save has no version")
		return {}
	var version := int(data["version"])
	if version > SaveData.VERSION:
		error.append("save version %d is newer than this game (%d)" % [version, SaveData.VERSION])
		return {}
	if version < 1:
		error.append("unknown save version %d" % version)
		return {}
	var current := data.duplicate(true)
	while version < SaveData.VERSION:
		match version:
			1:
				current = v1_to_v2(current)
			2:
				current = v2_to_v3(current)
		var next := int(current.get("version", version))
		if next <= version:
			error.append("no migration from save version %d" % version)
			return {}
		version = next
	return current


## v1 → v2: renames seed / pos, adds the player's yaw, the game time (08:00 of the first day),
## empty chunk deltas, no biome and the fox as species.
static func v1_to_v2(data: Dictionary) -> Dictionary:
	var at: Array = data.get("pos", [0.0, 0.0, 0.0])
	return {
		"version": 2,
		"world_seed": data.get("seed", 0),
		"player": {"position": at, "yaw": 0.0},
		"needs": data.get("needs", {}),
		"game_minutes": 480.0,
		"chunk_deltas": {"version": ChunkDeltaStore.VERSION, "chunks": []},
		"biome": "",
		"species": "res://data/species/fox.tres",
		"saved_at": 0,
	}


## v2 → v3: adds an empty explored area (the map starts blank).
static func v2_to_v3(data: Dictionary) -> Dictionary:
	var current := data.duplicate(true)
	current["version"] = 3
	current["explored"] = {}
	return current
