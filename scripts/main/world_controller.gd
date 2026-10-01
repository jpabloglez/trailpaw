class_name WorldController
extends Node3D
## The playable world: seeds it, sets up the floating origin, starts a new game at the spawn or
## restores a [SaveData] ([member pending_save], set before adding the scene), keeps the animal
## parked until the ground is ready ([AnimalSpawner]) and saves the game: on biome changes (at
## most every [member AutosaveSettings.biome_min_gap_seconds]), every
## [member AutosaveSettings.interval_seconds] and on [method save_now].
## [br][br]
## Budget: one timer per frame; saving (a few KB of JSON) happens at most every 30 s.

## Emitted after the game was saved.
signal game_saved

## Where a new game starts (absolute; the spawn meadow).
const NEW_GAME_POSITION: Vector3 = Vector3(32.0, 30.0, 32.0)

## Seed of a new game.
@export var world_seed: int = 12345
## When to save.
@export var autosave: AutosaveSettings
## Terrain streamer.
@export var streamer: WorldStreamer
## The player animal.
@export var animal: Animal
## Parks the animal until the ground is ready.
@export var spawner: AnimalSpawner
## Announces biomes (and triggers biome autosaves).
@export var biome_tracker: BiomeTracker

## Game to restore on start (null = new game with [member world_seed]).
var pending_save: SaveData
## Whether saving is allowed (off for the attract-mode world behind the menu).
var saving_enabled: bool = true

var _since_save: float = 0.0
var _needs: NeedsComponent


func _ready() -> void:
	_needs = animal.get_node("%NeedsComponent") as NeedsComponent
	FloatingOrigin.reset()
	FloatingOrigin.configure(streamer.terrain.chunk_size, streamer.streaming.rebase_distance)
	if pending_save != null:
		apply_save(pending_save)
	else:
		GameState.world_seed = world_seed
		_place_animal(NEW_GAME_POSITION, 0.0)
	FloatingOrigin.track(animal)
	spawner.park()
	EventBus.biome_entered.connect(_on_biome_entered)
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)


func _exit_tree() -> void:
	FloatingOrigin.reset()
	GameState.clock_scale = 1.0


func _process(delta: float) -> void:
	_since_save += delta
	if _since_save >= autosave.interval_seconds:
		save_now()


## Saves the game now (no-op while the animal waits for the ground or saving is off).
## Returns whether it saved.
func save_now() -> bool:
	if not saving_enabled or spawner.is_parked():
		return false
	if SaveSystem.write(collect_save()) != OK:
		return false
	_since_save = 0.0
	game_saved.emit()
	return true


## The current game as a [SaveData].
func collect_save() -> SaveData:
	var save := SaveData.new()
	save.world_seed = GameState.world_seed
	save.player_position = GameState.absolute_position(animal.global_position)
	save.player_yaw = animal.rotation.y
	for id in _needs.model.ids():
		save.needs[id] = _needs.value(id)
	save.game_minutes = GameState.game_minutes
	save.chunk_deltas = streamer.deltas().to_dict()
	save.biome = GameState.current_biome
	save.species = animal.movement.species.resource_path
	return save


## Restores [param save]: seed, time, eaten food, needs and the animal where it stood. Call
## before the world starts streaming (from [method _ready] via [member pending_save]).
func apply_save(save: SaveData) -> void:
	GameState.world_seed = save.world_seed
	GameState.game_minutes = save.game_minutes
	streamer.deltas().from_dict(save.chunk_deltas)
	for id: StringName in save.needs:
		if _needs.model.ids().has(id):
			_needs.set_value(id, save.needs[id])
	_place_animal(save.player_position, save.player_yaw)


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	var left := autosave.interval_seconds - _since_save
	return PackedStringArray(["seed %d  autosave in %.0f s" % [GameState.world_seed, left]])


## Puts the local origin at the chunk of [param absolute] and the animal there.
func _place_animal(absolute: Vector3, yaw: float) -> void:
	var size := streamer.terrain.chunk_size
	FloatingOrigin.start_at(Vector2i(floori(absolute.x / size), floori(absolute.z / size)))
	animal.position = GameState.local_position(absolute)
	animal.rotation.y = yaw
	animal.reset_physics_interpolation()


func _on_biome_entered(_id: StringName, _name: String) -> void:
	if _since_save >= autosave.biome_min_gap_seconds:
		save_now()
