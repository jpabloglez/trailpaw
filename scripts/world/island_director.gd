class_name IslandDirector
extends Node3D
## Builds the island treasures ([IslandPlan]) near the player and frees them when far, and tells
## the journal when the fox reaches one ([code]EventBus.island_reached[/code]).
## [br][br]
## - [b]An ancient tree:[/b] the oak, many times its usual size, with a trunk collider; its
##   crown shades the ground ([method is_shaded], asked through
##   [constant WorldStreamer.SHADE_GROUP]) and motes of light drift round it from dusk to dawn.
## - [b]Rare flowers:[/b] a ring of flowers in colours found nowhere else; resting among them
##   is as restful as a den ([method is_cosy], [constant Rester.COSY_GROUP]).
## - [b]An otter den:[/b] a heap of logs (the otters, Phase 19, gather there).
## [br][br]
## A treasure is one node in the floating-origin group. Budget: treasures are looked up once a
## second; cells already worked out (usually by the chunk workers) cost a dictionary lookup, and
## at most one new cell is worked out per lookup (≤ 5 ms, measured). Building a treasure is a
## handful of nodes, once.

## A treasure was built near the player ([param root] at its place, in the floating-origin
## group).
signal treasure_built(treasure: IslandTreasure, root: Node3D)

## Where the treasures are; none without [member TerrainSettings.islands].
@export var terrain: TerrainSettings
## The player; defaults to the [code]player[/code] group.
@export var player: Node3D

var _built: Dictionary[Vector2i, Node3D] = {}  # cell → its root
var _treasures: Dictionary[Vector2i, IslandTreasure] = {}
var _motes: Dictionary[Vector2i, GPUParticles3D] = {}
var _since: float = 1.0
var _sampler: HeightSampler
var _sampler_seed: int = -1
var _log_mesh: CylinderMesh
var _log_look: StandardMaterial3D
var _flower_mesh: ArrayMesh
var _flower_look: StandardMaterial3D


func _ready() -> void:
	add_to_group(WorldStreamer.SHADE_GROUP)
	add_to_group(Rester.COSY_GROUP)


func _process(delta: float) -> void:
	_since += delta
	if _since >= 1.0:
		_since = 0.0
		refresh()


## Builds treasures that came within reach, frees those left behind, reports the one reached
## and lights the ancient trees' motes at night.
func refresh() -> void:
	var focus := _player()
	if focus == null or terrain == null or terrain.islands == null:
		return
	var settings := terrain.islands
	var at := GameState.absolute_position(focus.global_position)
	for cell: Vector2i in _built.keys():
		var centre := _treasures[cell].centre
		if Vector2(centre.x - at.x, centre.z - at.z).length() > settings.free_radius:
			_built[cell].queue_free()
			_built.erase(cell)
			_treasures.erase(cell)
			_motes.erase(cell)
	var night := _is_night()
	for cell: Vector2i in _motes:
		_motes[cell].emitting = night
	for found in _nearby(at, settings):
		if not _built.has(found.cell):
			_build(found, settings)
		var d := Vector2(found.centre.x - at.x, found.centre.z - at.z).length()
		if d <= settings.discover_radius:
			EventBus.island_reached.emit(found.key(), found.kind, found.centre)


## Cells of the treasures built now.
func built_cells() -> Array[Vector2i]:
	return _built.keys()


## The node of the treasure of [param cell], or null.
func treasure_root(cell: Vector2i) -> Node3D:
	return _built.get(cell)


## The treasure of [param cell] built now, or null.
func treasure_of(cell: Vector2i) -> IslandTreasure:
	return _treasures.get(cell)


## Whether global position [param where] is in an ancient tree's shade.
func is_shaded(where: Vector3) -> bool:
	return _near_kind(where, IslandPlan.Treasure.ANCIENT_TREE)


## Whether global position [param where] is among rare flowers (restful as a den).
func is_cosy(where: Vector3) -> bool:
	return _near_kind(where, IslandPlan.Treasure.RARE_FLOWERS)


func _near_kind(where: Vector3, kind: int) -> bool:
	if terrain == null or terrain.islands == null:
		return false
	var settings := terrain.islands
	var radius := (
		settings.tree_shade
		if kind == IslandPlan.Treasure.ANCIENT_TREE
		else settings.flower_radius + 1.0
	)
	var at := GameState.absolute_position(where)
	for cell: Vector2i in _treasures:
		var found := _treasures[cell]
		if found.kind != kind:
			continue
		if Vector2(found.centre.x - at.x, found.centre.z - at.z).length() <= radius:
			return true
	return false


# Treasures within the build radius; works out at most one new cell this call.
func _nearby(at: Vector3, settings: IslandSettings) -> Array[IslandTreasure]:
	var out: Array[IslandTreasure] = []
	var sampler := _sampler_for()
	var r := settings.build_radius
	var lo := Vector2i(
		floori((at.x - r) / settings.cell_size), floori((at.z - r) / settings.cell_size)
	)
	var hi := Vector2i(
		floori((at.x + r) / settings.cell_size), floori((at.z + r) / settings.cell_size)
	)
	var budget := 1
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var cell := Vector2i(cx, cz)
			if not IslandPlan.is_cached(cell, GameState.world_seed):
				if budget == 0:
					continue
				budget -= 1
			var found := IslandPlan.treasure(
				cell, settings, sampler, GameState.world_seed, terrain.sea_level
			)
			if (
				found != null
				and Vector2(found.centre.x - at.x, found.centre.z - at.z).length() <= r
			):
				out.append(found)
	return out


func _build(found: IslandTreasure, settings: IslandSettings) -> void:
	var root := Node3D.new()
	root.name = "Treasure_%d_%d" % [found.cell.x, found.cell.y]
	root.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
	add_child(root)
	root.global_position = GameState.local_position(found.centre)
	var rng := RandomNumberGenerator.new()
	rng.seed = found.seed
	match found.kind:
		IslandPlan.Treasure.ANCIENT_TREE:
			_ancient_tree(root, found, settings, rng)
		IslandPlan.Treasure.RARE_FLOWERS:
			root.add_child(_flower_ring(found, settings, rng))
		IslandPlan.Treasure.OTTER_DEN:
			root.add_child(_den(settings, rng))
	_built[found.cell] = root
	_treasures[found.cell] = found
	treasure_built.emit(found, root)


func _ancient_tree(
	root: Node3D, found: IslandTreasure, settings: IslandSettings, rng: RandomNumberGenerator
) -> void:
	var tree: Node3D
	var streamer := get_tree().get_first_node_in_group(WorldStreamer.GROUP) as WorldStreamer
	var mesh := streamer.vegetation_mesh(settings.tree_type.id) if streamer != null else null
	if mesh != null:  # the same foliage look and colours as the oaks of the chunks
		var shown := MeshInstance3D.new()
		shown.mesh = mesh
		tree = shown
	else:
		tree = settings.tree_type.scene.instantiate()
	tree.name = "AncientTree"
	tree.scale = Vector3.ONE * settings.tree_scale
	tree.rotation.y = rng.randf() * TAU
	tree.position.y = -0.3  # roots into the slope
	root.add_child(tree)
	var body := StaticBody3D.new()  # the trunk: the fox walks round it
	body.name = "Trunk"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = settings.tree_trunk
	cylinder.height = 6.0
	shape.shape = cylinder
	shape.position.y = 3.0
	body.add_child(shape)
	root.add_child(body)
	if Settings.quality != null and not Settings.quality.motion_effects:
		return
	var motes := GPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = settings.motes
	motes.lifetime = 6.0
	motes.emitting = _is_night()
	motes.position.y = settings.tree_scale * 0.55
	motes.visibility_aabb = AABB(Vector3(-12, -8, -12), Vector3(24, 16, 24))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = settings.tree_shade
	process.gravity = Vector3(0.0, 0.05, 0.0)
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.direction = Vector3.UP
	process.spread = 180.0
	motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.22
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	look.albedo_color = settings.mote_color
	look.emission_enabled = true
	look.emission = settings.mote_color
	quad.material = look
	motes.draw_pass_1 = quad
	root.add_child(motes)
	_motes[found.cell] = motes


## Where the rare flowers of [param found] grow (relative to its top) and their colours,
## deterministic per treasure ([member IslandTreasure.seed]).
static func flower_layout(
	found: IslandTreasure, settings: IslandSettings, sampler: HeightSampler
) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = found.seed
	var places := PackedVector3Array()
	var colours := PackedColorArray()
	for i in settings.flowers:
		var spread := sqrt(rng.randf()) * settings.flower_radius
		var along := Vector2.from_angle(rng.randf() * TAU) * spread
		var ground := (
			sampler.height_at(found.centre.x + along.x, found.centre.z + along.y) - found.centre.y
		)
		places.append(Vector3(along.x, ground, along.y))
		colours.append(settings.flower_colors[rng.randi() % settings.flower_colors.size()])
	return [places, colours]


func _flower_ring(
	found: IslandTreasure, settings: IslandSettings, rng: RandomNumberGenerator
) -> MultiMeshInstance3D:
	if _flower_mesh == null:
		_flower_mesh = ProceduralMeshes.rare_flower()
		_flower_look = StandardMaterial3D.new()
		_flower_look.vertex_color_use_as_albedo = true
		_flower_look.roughness = 0.7
	var layout := flower_layout(found, settings, _sampler_for())
	var places: PackedVector3Array = layout[0]
	var colours: PackedColorArray = layout[1]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _flower_mesh
	multimesh.instance_count = places.size()
	for i in places.size():
		var size := rng.randf_range(1.8, 2.5)  # knee-high to the fox: a meadow of its own
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
		multimesh.set_instance_transform(i, Transform3D(basis, places[i]))
		multimesh.set_instance_color(i, colours[i])
	var node := MultiMeshInstance3D.new()
	node.name = "RareFlowers"
	node.multimesh = multimesh
	node.material_override = _flower_look
	return node


# A heap of logs leaning together, with a gap facing the water for the way in.
func _den(settings: IslandSettings, rng: RandomNumberGenerator) -> Node3D:
	if _log_mesh == null:
		_log_mesh = CylinderMesh.new()
		_log_mesh.top_radius = 0.17
		_log_mesh.bottom_radius = 0.21
		_log_mesh.height = 2.6
		_log_mesh.radial_segments = 7
		_log_mesh.rings = 1
		_log_look = StandardMaterial3D.new()
		_log_look.albedo_color = Color(0.42, 0.3, 0.2)
		_log_look.roughness = 0.95
		_log_mesh.material = _log_look
	var den := Node3D.new()
	den.name = "OtterDen"
	var gap := rng.randf() * TAU  # the way in
	for i in settings.den_logs:
		var around := gap + (i + 0.5) / settings.den_logs * (TAU - 0.9) + 0.45
		var log_node := MeshInstance3D.new()
		log_node.mesh = _log_mesh
		var out := Vector3(cos(around), 0.0, sin(around))
		var lean := Basis(
			out.cross(Vector3.UP).normalized(), deg_to_rad(rng.randf_range(48.0, 60.0))
		)
		log_node.basis = lean * Basis(Vector3.UP, rng.randf() * TAU)
		log_node.position = out * 0.55 + Vector3.UP * 0.75
		den.add_child(log_node)
	return den


func _is_night() -> bool:
	var hour := GameState.time_of_day() / 60.0
	return hour >= 19.0 or hour < 6.0


func _sampler_for() -> HeightSampler:
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed
	return _sampler


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
