class_name FaunaDirector
extends Node3D
## Brings the world to life around the player: each full-detail (LOD 0) chunk rolls its herd
## with [FaunaPlan] when it loads, agents appear on the ground (dry, not too steep, never right
## next to the player), and leave when their chunk stops being full detail or they fall beyond
## [member FaunaSettings.despawn_distance]. At most [member FaunaSettings.max_agents] live at once.
##
## AI LOD by distance to the player: full rate within [member FaunaSettings.full_radius], a
## slower brain, movement every [member FaunaSettings.mid_stride] ticks and no ground alignment up
## to [member FaunaSettings.mid_radius], frozen (no
## physics, no animation) beyond.
## [br][br]
## Budget: spawns are queued and started ≤ [member FaunaSettings.spawns_per_frame] per frame
## (≈ 1 ms each: a model instance and an animation tree over a shared clip library, after
## [method warm_up]); LOD and despawn checks run at 4 Hz over ≤ 10 agents. The AI itself costs
## ≈ 0.65 ms/frame for 10 animals at full rate (measured, WSL).

## LOD tiers.
enum Tier { FULL, MID, FROZEN }

## LOD and despawn checks per second.
const CHECK_HZ: float = 4.0

## Population and LOD.
@export var settings: FaunaSettings
## Terrain settings (chunk size, biome table).
@export var terrain: TerrainSettings
## Source of loaded chunks (optional; tests call [method sync] directly).
@export var streamer: WorldStreamer
## Scene instanced for each animal.
@export var agent_scene: PackedScene
## The player (distances, spawn clearance); defaults to the [code]player[/code] group.
@export var player: Node3D

var _agents: Array[FaunaAgent] = []
var _agent_chunk: Dictionary[FaunaAgent, Vector2i] = {}
var _rolled: Dictionary[Vector2i, bool] = {}
var _queue: Array = []
var _resolver: BiomeResolver
var _since_check: float = 0.0
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_ray.collision_mask = 1
	if streamer != null:
		streamer.chunks_changed.connect(sync_from_streamer)
	add_to_group(WorldStreamer.DEBUG_LINES_GROUP)
	warm_up()


## Instances every species of the biome tables once, out of sight, so their one-off costs
## (first model instance, shared clip library) are paid while loading rather than when the
## first herd appears (~5 ms each).
func warm_up() -> void:
	if terrain == null or terrain.biomes == null or agent_scene == null:
		return
	var seen := {}
	for biome in terrain.biomes.biomes:
		for entry in biome.fauna:
			if entry.species == null or seen.has(entry.species):
				continue
			seen[entry.species] = true
			var agent := agent_scene.instantiate() as FaunaAgent
			agent.fauna = entry.species
			agent.process_mode = Node.PROCESS_MODE_DISABLED
			agent.visible = false
			agent.position = Vector3(0.0, -10000.0, 0.0)
			add_child(agent)
			agent.free()


func _process(delta: float) -> void:
	for i in settings.spawns_per_frame:
		if _queue.is_empty():
			break
		_spawn(_queue.pop_front())
	_since_check += delta
	if _since_check >= 1.0 / CHECK_HZ:
		_since_check = 0.0
		update_agents()


## Syncs with the [member streamer]'s full-detail chunks.
func sync_from_streamer() -> void:
	var lod0: Array[Vector2i] = []
	for coord in streamer.loaded_coords():
		if streamer.get_chunk(coord).lod == 0:
			lod0.append(coord)
	sync(lod0)


## Rolls newly available full-detail chunks and removes animals whose chunk is gone.
func sync(lod0_coords: Array[Vector2i]) -> void:
	var available := {}
	for coord in lod0_coords:
		available[coord] = true
	for agent: FaunaAgent in _agents.duplicate():
		if not available.has(_agent_chunk[agent]):
			_despawn(agent)
	for coord: Vector2i in _rolled.keys():
		if not available.has(coord):
			_rolled.erase(coord)  # rolls again (identically) when it comes back
	_queue = _queue.filter(func(spawn: Array) -> bool: return available.has(spawn[3]))
	for coord in lod0_coords:
		if _rolled.has(coord):
			continue
		_rolled[coord] = true
		for spawn: Array in FaunaPlan.roll(
			coord, terrain.chunk_size, _biome_at(coord), GameState.world_seed, settings.herd_spread
		):
			_queue.append([spawn[0], spawn[1], spawn[2], coord])


## Applies the AI LOD and removes animals that wandered too far from the player.
func update_agents() -> void:
	var focus := _player()
	if focus == null:
		return
	for agent: FaunaAgent in _agents.duplicate():
		var distance := agent.horizontal_distance_to(focus.global_position)
		if distance > settings.despawn_distance:
			_despawn(agent)
			continue
		set_tier(agent, tier_for(distance))


## LOD tier for an animal [param distance] metres from the player.
func tier_for(distance: float) -> Tier:
	if distance <= settings.full_radius:
		return Tier.FULL
	if distance <= settings.mid_radius:
		return Tier.MID
	return Tier.FROZEN


## Puts [param agent] in [param tier].
func set_tier(agent: FaunaAgent, tier: Tier) -> void:
	var voice := agent.get_node_or_null("%Voice") as AnimalVoice
	if voice != null:
		voice.enabled = tier == Tier.FULL  # only nearby animals call
	if tier == Tier.FROZEN:
		agent.process_mode = Node.PROCESS_MODE_DISABLED
		return
	agent.process_mode = Node.PROCESS_MODE_INHERIT
	var aligner := agent.get_node_or_null("%GroundAligner") as GroundAligner
	if aligner != null:
		aligner.level = tier != Tier.FULL  # no ground probes beyond the full-detail radius
	agent.tick_stride = 1 if tier == Tier.FULL else settings.mid_stride
	if agent.brain != null:
		agent.brain.tick_hz = settings.full_hz if tier == Tier.FULL else settings.mid_hz


## Animals alive now.
func agents() -> Array[FaunaAgent]:
	return _agents


## Spawns still waiting (tests and tools).
func pending() -> int:
	return _queue.size()


## Lines for the F3 overlay.
func get_debug_lines() -> PackedStringArray:
	var tiers := [0, 0, 0]
	var focus := _player()
	if focus != null:
		for agent in _agents:
			tiers[tier_for(agent.horizontal_distance_to(focus.global_position))] += 1
	return PackedStringArray(
		[
			(
				"fauna %d/%d (full %d, mid %d, frozen %d) queued %d"
				% [
					_agents.size(),
					settings.max_agents,
					tiers[0],
					tiers[1],
					tiers[2],
					_queue.size(),
				]
			)
		]
	)


func _spawn(spawn: Array) -> void:
	if _agents.size() >= settings.max_agents:
		return
	var species: FaunaSpecies = spawn[0]
	var absolute_xz: Vector2 = spawn[1]
	var local := GameState.local_position(Vector3(absolute_xz.x, 0.0, absolute_xz.y))
	var focus := _player()
	if focus != null:
		var d := Vector2(local.x - focus.global_position.x, local.z - focus.global_position.z)
		if d.length() < settings.min_spawn_distance:
			return
	var ground := _ground_at(local)
	if ground == Vector3.INF:
		return
	var agent := agent_scene.instantiate() as FaunaAgent
	agent.fauna = species
	agent.decision_seed = spawn[2]
	agent.position = ground + Vector3.UP * 0.1
	agent.rotation.y = float(spawn[2] % 628) / 100.0
	add_child(agent)
	_agents.append(agent)
	_agent_chunk[agent] = spawn[3]


func _despawn(agent: FaunaAgent) -> void:
	_agents.erase(agent)
	_agent_chunk.erase(agent)
	agent.queue_free()


## Dry, gentle ground under [param local] (INF when unsuitable or not loaded).
func _ground_at(local: Vector3) -> Vector3:
	_ray.from = Vector3(local.x, 300.0, local.z)
	_ray.to = Vector3(local.x, -300.0, local.z)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return Vector3.INF
	var at: Vector3 = hit.position
	if at.y < GameState.water_level + 0.3:
		return Vector3.INF
	if (hit.normal as Vector3).y < cos(deg_to_rad(settings.max_spawn_slope)):
		return Vector3.INF
	return at


func _biome_at(coord: Vector2i) -> BiomeDefinition:
	if terrain == null or terrain.biomes == null:
		return null
	if _resolver == null:
		_resolver = BiomeResolver.new(terrain.biomes, GameState.world_seed)
	var centre := (Vector2(coord) + Vector2(0.5, 0.5)) * terrain.chunk_size
	return _resolver.dominant_at(centre.x, centre.y)


func _player() -> Node3D:
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
	return player
