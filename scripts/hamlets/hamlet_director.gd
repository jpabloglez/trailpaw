class_name HamletDirector
extends Node3D
## Builds the rural hamlets ([HamletPlan]) near the player and frees them when far: each piece's
## model at its place, solid pieces with box colliders on the world layer (the fox walks round
## houses, the well and fences), windows that glow at night and chimney smoke (off on Low).
## A hamlet is one node in the floating-origin group, its pieces placed relative to its well.
## [br][br]
## Hamlets farther away, up to [member HamletSettings.plume_radius], show only a tall, slow smoke
## plume above their roofs: a clue seen across the land (it ignores the distance fog, so it reads
## above the hazy horizon). It hands over to the chimneys when the hamlet is built.
## [br][br]
## Budget: hamlets are looked up once a second (cached per cell); building is spread over frames,
## ≤ 1 piece per frame; the window glow is one shared material updated once a second.

## A hamlet was built near the player: [param root] is its node (at the well, in the
## floating-origin group); its pieces follow over the next frames.
signal hamlet_built(layout: HamletLayout, root: Node3D)
## The hamlet of [param cell] was freed (its root and everything under it).
signal hamlet_freed(cell: Vector2i)

static var _bounds: Dictionary[StringName, AABB] = {}

## Hamlets closer than this are built (m).
@export_range(50.0, 1000.0, 10.0, "suffix:m") var build_radius: float = 300.0
## Built hamlets farther than this are freed (m).
@export_range(50.0, 1500.0, 10.0, "suffix:m") var free_radius: float = 400.0
## Terrain (heights, biomes, and [member TerrainSettings.hamlets]).
@export var terrain: TerrainSettings
## The player; defaults to the [code]player[/code] group.
@export var player: Node3D
## Day and night (windows glow in the dark; optional).
@export var day_night: DayNightCycle

var _built: Dictionary[Vector2i, Node3D] = {}  # cell → its root
var _layouts: Dictionary[Vector2i, HamletLayout] = {}
var _queue: Array[Array] = []  # [cell, piece index] still to build
var _since: float = 1.0
var _sampler: HeightSampler
var _sampler_seed: int = -1
var _windows: StandardMaterial3D
var _plumes: Dictionary[Vector2i, GPUParticles3D] = {}
var _plume_look: StandardMaterial3D
var _smoke_texture: Texture2D


func _ready() -> void:
	_windows = StandardMaterial3D.new()
	_windows.albedo_color = Color(0.2, 0.24, 0.3)
	_windows.roughness = 0.2
	_windows.emission_enabled = true
	_windows.emission = Color(1.0, 0.72, 0.38)
	_windows.emission_energy_multiplier = 0.0


func _process(delta: float) -> void:
	_since += delta
	if _since >= 1.0:
		_since = 0.0
		refresh()
		_update_glow()
	if not _queue.is_empty():
		_build_next()


## Builds hamlets that came within reach and frees those left behind (the pieces themselves are
## built a few per frame afterwards).
func refresh() -> void:
	var focus := _player()
	if focus == null or terrain == null or terrain.hamlets == null:
		return
	var at := GameState.absolute_position(focus.global_position)
	_refresh_plumes(at)
	for cell: Vector2i in _built.keys():
		var centre := _layouts[cell].centre
		if Vector2(centre.x - at.x, centre.z - at.z).length() > free_radius:
			_built[cell].queue_free()
			_built.erase(cell)
			_layouts.erase(cell)
			_queue = _queue.filter(func(item: Array) -> bool: return item[0] != cell)
			hamlet_freed.emit(cell)
	for hamlet in hamlets_near(at, build_radius):
		if _built.has(hamlet.cell):
			continue
		var root := Node3D.new()
		root.name = "Hamlet_%d_%d" % [hamlet.cell.x, hamlet.cell.y]
		root.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
		add_child(root)
		root.global_position = GameState.local_position(hamlet.centre)
		_built[hamlet.cell] = root
		_layouts[hamlet.cell] = hamlet
		for i in hamlet.size():
			_queue.append([hamlet.cell, i])
		hamlet_built.emit(hamlet, root)


## The far plume of the hamlet of [param cell] (null when it has none).
func plume_of(cell: Vector2i) -> GPUParticles3D:
	return _plumes.get(cell)


## Builds everything still queued now (tests and tools).
func build_all_now() -> void:
	while not _queue.is_empty():
		_build_next()


## Hamlets whose well is within [param radius] of absolute [param at].
func hamlets_near(at: Vector3, radius: float) -> Array[HamletLayout]:
	return HamletPlan.near(
		at.x,
		at.z,
		radius,
		terrain.hamlets,
		_height_sampler(),
		GameState.world_seed,
		terrain.sea_level
	)


## Cells of the hamlets built now.
func built_cells() -> Array[Vector2i]:
	return _built.keys()


## The root node of the hamlet of [param cell] (null when not built).
func hamlet_root(cell: Vector2i) -> Node3D:
	return _built.get(cell)


## Pieces still waiting to be built.
func pending() -> int:
	return _queue.size()


## How bright windows glow now (0 by day … 1 at night).
func glow() -> float:
	return _windows.emission_energy_multiplier / 2.5


func _build_next() -> void:
	var item: Array = _queue.pop_front()
	var cell: Vector2i = item[0]
	var hamlet := _layouts[cell]
	var root := _built[cell]
	var i: int = item[1]
	var piece := terrain.hamlets.piece(hamlet.ids[i])
	var holder := Node3D.new()
	holder.name = "%s_%d" % [piece.id, i]
	root.add_child(holder)
	holder.position = hamlet.positions[i] - hamlet.centre
	holder.rotation.y = hamlet.yaws[i] + deg_to_rad(piece.yaw_offset)
	if piece.scene == null:
		return  # a place (the patch, the nest): filled by others
	var model: Node3D = piece.scene.instantiate()
	model.scale = Vector3.ONE * terrain.hamlets.model_scale
	holder.add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(s)
			if material != null and material.resource_name == "Windows":
				mesh.set_surface_override_material(s, _windows)
	var box := _model_bounds(piece.id, holder, model)
	if piece.solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1  # world
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = box.size
		shape.shape = cube
		shape.position = box.get_center()
		body.add_child(shape)
		holder.add_child(body)
	if piece.smoke and (Settings.quality == null or Settings.quality.motion_effects):
		holder.add_child(
			_smoke(Vector3(box.get_center().x, box.size.y * piece.smoke_height, box.get_center().z))
		)


# Bounds of a piece's model in its holder's space (cached per piece id).
func _model_bounds(id: StringName, holder: Node3D, model: Node3D) -> AABB:
	if _bounds.has(id):
		return _bounds[id]
	var box := AABB()
	var first := true
	var to_holder := holder.global_transform.affine_inverse()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = to_holder * mesh.global_transform * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	_bounds[id] = box
	return box


func _smoke(at: Vector3) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = at
	smoke.amount = 10
	smoke.lifetime = 5.0
	smoke.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 0.8
	process.gravity = Vector3(0.15, 0.1, 0.0)  # drifts a little with the breeze
	process.scale_min = 0.8
	process.scale_max = 1.5
	var grow := Curve.new()
	grow.max_value = 2.0  # points above the default 1 would be clamped
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(0.75, 0.75, 0.75, 0.45))
	fade.set_color(1, Color(0.8, 0.8, 0.8, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	smoke.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = MotionEffects.soft_dot()
	quad.material = look
	smoke.draw_pass_1 = quad
	return smoke


# Plumes for hamlets within plume_radius that are not built; none on the Low preset.
func _refresh_plumes(at: Vector3) -> void:
	var settings := terrain.hamlets
	var wanted := {}
	if Settings.quality == null or Settings.quality.motion_effects:
		for hamlet in hamlets_near(at, settings.plume_radius):
			if not _built.has(hamlet.cell) and not _is_close(hamlet, at):
				wanted[hamlet.cell] = hamlet
	for cell: Vector2i in _plumes.keys():
		if not wanted.has(cell):
			_plumes[cell].queue_free()
			_plumes.erase(cell)
	for cell: Vector2i in wanted:
		if _plumes.has(cell):
			continue
		var hamlet: HamletLayout = wanted[cell]
		var plume := _plume(settings.plume_height)
		plume.name = "Plume_%d_%d" % [cell.x, cell.y]
		plume.add_to_group(FloatingOrigin.SHIFTABLE_GROUP)
		add_child(plume)
		plume.global_position = GameState.local_position(hamlet.centre) + Vector3.UP * 8.0
		_plumes[cell] = plume


func _is_close(hamlet: HamletLayout, at: Vector3) -> bool:
	return Vector2(hamlet.centre.x - at.x, hamlet.centre.z - at.z).length() <= build_radius


# A tall, slow column of pale smoke rising [param height] metres (a plume seen from afar).
func _plume(height: float) -> GPUParticles3D:
	var plume := GPUParticles3D.new()
	plume.amount = 48
	plume.lifetime = 14.0
	plume.preprocess = 14.0  # already risen when it appears
	plume.local_coords = false
	plume.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, height + 40.0, 80))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 6.0
	var speed := height / 14.0
	process.initial_velocity_min = speed * 0.85
	process.initial_velocity_max = speed * 1.15
	process.gravity = Vector3(0.12, 0.0, 0.05)  # leans a little with the breeze
	process.scale_min = 1.0
	process.scale_max = 1.5
	var grow := Curve.new()
	grow.max_value = 3.0  # points above the default 1 would be clamped
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 2.5))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	# Grey rather than white: it must stand out against the pale sky near the horizon.
	fade.set_color(0, Color(0.55, 0.55, 0.57, 0.8))
	fade.set_color(1, Color(0.72, 0.72, 0.74, 0.0))
	fade.add_point(0.6, Color(0.64, 0.64, 0.66, 0.7))  # still thick as it spreads
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	plume.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(16.0, 16.0)  # a few pixels wide even a kilometre away
	quad.material = _plume_material()
	plume.draw_pass_1 = quad
	return plume


func _plume_material() -> StandardMaterial3D:
	if _plume_look == null:
		_plume_look = StandardMaterial3D.new()
		_plume_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_plume_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_plume_look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_plume_look.vertex_color_use_as_albedo = true
		_plume_look.albedo_texture = MotionEffects.soft_dot()
		_plume_look.disable_fog = true  # a clue above the hazy horizon
	return _plume_look


func _update_glow() -> void:
	var dark := 0.0
	if day_night != null:
		var hour := GameState.time_of_day() / 60.0
		dark = DayCurve.sample(day_night.settings.key_hours, day_night.settings.stars, hour)
	_windows.emission_energy_multiplier = 2.5 * dark
	if _plume_look != null:  # dimmer against the night sky
		_plume_look.albedo_color = Color(1.0, 1.0, 1.0, lerpf(1.0, 0.4, dark))


func _height_sampler() -> HeightSampler:
	if _sampler == null or _sampler_seed != GameState.world_seed:
		_sampler = HeightSampler.new(terrain, GameState.world_seed)
		_sampler_seed = GameState.world_seed
	return _sampler


func _player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group(Animal.PLAYER_GROUP) as Node3D
