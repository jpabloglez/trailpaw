class_name SaveData
extends RefCounted
## Everything needed to continue a game exactly where it was left: the world seed, where the
## player stands (absolute, so floating-origin rebases do not matter), its needs, the game time
## (which also fixes the weather), what the player changed in the world (eaten food) and the
## area explored so far (for the map).
##
## Saved as plain JSON through [method to_dict] / [method from_dict] — never as a resource,
## because loading a resource can run scripts and a save file is user-editable. Older files are
## upgraded by [SaveMigrations] first.

## Current schema version (see [SaveMigrations] for the history).
const VERSION: int = 3

## World seed.
var world_seed: int = 0
## Player position in absolute world coordinates (m).
var player_position: Vector3 = Vector3.ZERO
## Player heading (radians).
var player_yaw: float = 0.0
## Need id → value.
var needs: Dictionary[StringName, float] = {}
## Game clock ([code]GameState.game_minutes[/code]).
var game_minutes: float = 0.0
## Per-chunk resource deltas ([method ChunkDeltaStore.to_dict]).
var chunk_deltas: Dictionary = {}
## Biome the player was in.
var biome: StringName = &""
## Player species resource path.
var species: String = ""
## When it was saved (Unix time, s).
var saved_at: int = 0
## Explored area and scented water ([method ExploredMap.to_dict]).
var explored: Dictionary = {}


## Plain, JSON-friendly copy (current [constant VERSION]).
func to_dict() -> Dictionary:
	var need_values := {}
	for id: StringName in needs:
		need_values[String(id)] = needs[id]
	return {
		"version": VERSION,
		"world_seed": world_seed,
		"player":
		{
			"position": [player_position.x, player_position.y, player_position.z],
			"yaw": player_yaw,
		},
		"needs": need_values,
		"game_minutes": game_minutes,
		"chunk_deltas": chunk_deltas,
		"biome": String(biome),
		"species": species,
		"saved_at": saved_at,
		"explored": explored,
	}


## A [SaveData] from a current-version [param data] (run [method SaveMigrations.migrate]
## first). Missing fields keep their defaults; numbers are coerced (JSON has only floats).
static func from_dict(data: Dictionary) -> SaveData:
	var save := SaveData.new()
	save.world_seed = int(data.get("world_seed", 0))
	var player: Dictionary = data.get("player", {})
	var at: Array = player.get("position", [0.0, 0.0, 0.0])
	if at.size() == 3:
		save.player_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	save.player_yaw = float(player.get("yaw", 0.0))
	var need_values: Dictionary = data.get("needs", {})
	for id: String in need_values:
		save.needs[StringName(id)] = float(need_values[id])
	save.game_minutes = float(data.get("game_minutes", 0.0))
	save.chunk_deltas = data.get("chunk_deltas", {})
	save.biome = StringName(str(data.get("biome", "")))
	save.species = str(data.get("species", ""))
	save.saved_at = int(data.get("saved_at", 0))
	save.explored = data.get("explored", {})
	return save
