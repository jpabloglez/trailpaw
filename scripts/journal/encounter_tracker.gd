class_name EncounterTracker
extends Node
## Fills the [AnimalJournal]: an animal counts as met once it has stayed close to the player
## ([member JournalEntry.sight_radius]) and on screen (inside the current camera's view) for
## [member JournalSettings.sight_seconds]. Fireflies count once they glow around the player.
## The first time, [code]EventBus.animal_discovered[/code] fires.
## It also records the biomes entered ([code]EventBus.biome_entered[/code]); a first visit
## fires [code]EventBus.biome_discovered[/code] (not for the biome where the journal starts).
## [br][br]
## Budget: [member JournalSettings.check_hz] checks per second; each looks only at entries not
## yet seen, with a distance test (and a frustum test when close) per animal of their system —
## ≈ 10 agents, 120 critters (plus a few dozen in the trees), 60 birds and 24 fliers at most;
## no allocations. Measured in the
## world at the spawn with nothing met yet (the worst case): p50 0.07 ms, p99 0.23 ms per check.

## Entries and what counts as an encounter.
@export var settings: JournalSettings
## The player (distances are measured from it); defaults to the [code]player[/code] group.
@export var player: Node3D
## Where the animals are (each optional).
@export var fauna: FaunaDirector
@export var critters: CritterSystem
@export var tree_life: TreeLife
@export var farm: FarmLife
@export var birds: BirdFlocks
@export var flitters: Array[Flitters] = []
@export var fireflies: Fireflies
## The camera that must see them; defaults to the viewport's.
@export var camera: Camera3D

## What has been met.
var journal := AnimalJournal.new()

var _since: float = 0.0
var _in_sight := PackedFloat32Array()  # per entry: seconds in sight so far


func _ready() -> void:
	_in_sight.resize(settings.entries.size())
	EventBus.biome_entered.connect(_on_biome_entered)


func _process(delta: float) -> void:
	_since += delta
	if _since >= 1.0 / settings.check_hz:
		check(_since)
		_since = 0.0


## Looks for animals in sight now; [param elapsed] seconds passed since the last check.
func check(elapsed: float) -> void:
	var focus := _player()
	var eye := _camera()
	if focus == null:
		return
	var at := focus.global_position
	for e in settings.entries.size():
		var entry := settings.entries[e]
		if journal.is_seen(entry.id):
			continue
		if not _sees(entry, at, eye):
			_in_sight[e] = 0.0
			continue
		_in_sight[e] += elapsed
		var needed := entry.sight_seconds if entry.sight_seconds > 0.0 else settings.sight_seconds
		if _in_sight[e] >= needed:
			if journal.discover(entry.id, GameState.game_minutes, GameState.current_biome):
				EventBus.animal_discovered.emit(entry.id)


# Records the biome entered; not while disabled (the main menu's world, which watches its
# camera fly over the land).
func _on_biome_entered(id: StringName, _display_name: String) -> void:
	if not can_process():
		return
	var focus := _player()
	var at := GameState.absolute_position(focus.global_position) if focus != null else Vector3.ZERO
	var first := journal.visited_count() == 0
	if journal.visit_biome(id, GameState.game_minutes, at) and not first:
		EventBus.biome_discovered.emit(id)


# Whether an animal of [param entry] is close to [param at] and on screen now.
func _sees(entry: JournalEntry, at: Vector3, eye: Camera3D) -> bool:
	var reach := entry.sight_radius
	match entry.source:
		JournalEntry.Source.FAUNA:
			if fauna != null:
				for agent in fauna.agents():
					if (
						agent.fauna == entry.animal
						and _in_view(agent.global_position, at, reach, eye)
					):
						return true
		JournalEntry.Source.CRITTER, JournalEntry.Source.FARM:
			for system: Node in [critters, tree_life, farm]:  # the same interface
				if system == null:
					continue
				for i in system.count():
					if system.kind_of(i) != entry.animal or not system.is_shown(i):
						continue
					var where: Vector3 = system.position_of(i)
					if system is Node3D:  # critter systems give local positions
						where = (system as Node3D).to_global(where)
					if _in_view(where, at, reach, eye):
						return true
		JournalEntry.Source.BIRD:
			if birds != null and birds.settings == entry.animal:
				for b in birds.count():
					if _in_view(birds.to_global(birds.position_of(b)), at, reach, eye):
						return true
		JournalEntry.Source.FLITTER:
			for node in flitters:
				if node == null or node.kind != entry.animal:
					continue
				for i in node.count():
					if _in_view(node.position_of(i), at, reach, eye):
						return true
		JournalEntry.Source.FIREFLY:
			return (
				fireflies != null
				and fireflies.settings == entry.animal
				and fireflies.emitting
				and fireflies.amount_ratio >= settings.firefly_glow
			)
	return false


func _in_view(where: Vector3, at: Vector3, reach: float, eye: Camera3D) -> bool:
	if where.distance_squared_to(at) > reach * reach:
		return false
	return eye == null or on_screen(eye, where + Vector3.UP * 0.15)


## Whether [param where] is in front of [param eye] and inside its field of view (the frustum's
## side planes, ignoring near and far). Done by hand: [method Camera3D.is_position_in_frustum]
## depends on the renderer's frustum, which the headless one never computes.
static func on_screen(eye: Camera3D, where: Vector3) -> bool:
	var local := eye.global_transform.affine_inverse() * where
	if local.z >= 0.0:
		return false  # behind the camera
	var size := eye.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var tan_half := tan(deg_to_rad(eye.fov) * 0.5)
	var depth := -local.z
	return absf(local.y) <= tan_half * depth and absf(local.x) <= tan_half * aspect * depth


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
