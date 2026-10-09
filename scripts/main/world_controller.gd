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
## Remembers the explored area for the map (optional).
@export var exploration: ExplorationTracker
## The animals met (optional; saved and restored).
@export var encounters: EncounterTracker
## Builds the rural hamlets nearby (optional; the map marks those explored).
@export var hamlets: HamletDirector

## Game to restore on start (null = new game with [member world_seed]).
var pending_save: SaveData
## Whether saving is allowed (off for the attract-mode world behind the menu).
var saving_enabled: bool = true
## The world behind the main menu: no player, no HUD, no saving, a gliding camera (set before
## adding the scene).
var attract_mode: bool = false

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
		if not attract_mode:
			GameState.game_minutes = GameState.CLOCK.start_minutes
		_place_animal(NEW_GAME_POSITION, 0.0)
	FloatingOrigin.track(animal)
	spawner.park()
	if attract_mode:
		_enter_attract_mode()
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
	if exploration != null:
		save.explored = exploration.explored.to_dict()
	if encounters != null:
		save.journal = encounters.journal.to_dict()
	return save


## Restores [param save]: seed, time, eaten food, needs and the animal where it stood. Call
## before the world starts streaming (from [method _ready] via [member pending_save]).
func apply_save(save: SaveData) -> void:
	GameState.world_seed = save.world_seed
	GameState.game_minutes = save.game_minutes
	streamer.deltas().from_dict(save.chunk_deltas)
	if exploration != null:
		exploration.explored.from_dict(save.explored)
	if encounters != null:
		encounters.journal.from_dict(save.journal)
	for id: StringName in save.needs:
		if _needs.model.ids().has(id):
			_needs.set_value(id, save.needs[id])
	_place_animal(save.player_position, save.player_yaw)


## The camera of the attract mode, or null.
func attract_camera() -> AttractCamera:
	return get_node_or_null("AttractCamera") as AttractCamera


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


func _enter_attract_mode() -> void:
	saving_enabled = false
	spawner.auto_release = false
	animal.visible = false
	for child in get_children():
		if child is CanvasLayer:
			child.queue_free()  # HUD, prompt, toasts: some show themselves on events
		elif child is CameraRig or child is ExplorationTracker or child is EncounterTracker:
			(child as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var camera := AttractCamera.new()
	camera.name = "AttractCamera"
	camera.far = 2000.0
	add_child(camera)
	camera.begin(animal.position, streamer.terrain)
	streamer.target = camera
	FloatingOrigin.track(camera)
	if biome_tracker != null:
		biome_tracker.target = camera


func _on_biome_entered(_id: StringName, _name: String) -> void:
	if _since_save >= autosave.biome_min_gap_seconds:
		save_now()
