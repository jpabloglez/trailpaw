class_name PortraitStudio
extends SubViewport
## A tiny photo studio for the journal: renders one animal ([JournalEntry]) in its own 3D world on
## a transparent background, framed automatically from its size and seen from its left front.
## [member spin] turns it (the new-animal card); [method snapshot] renders it once into a
## texture, cached per entry for the session (the journal screen).
## [br][br]
## Figures: fauna use their game model in the idle pose; the others are their procedural mesh
## with a vertex-colour material (wings spread in their rest pose), tinted like in the game.

## Seen this far round from the front (rad) and from this far above (rad): walkers from a little
## above, fliers (their wings spread flat) from well above.
const VIEW_YAW: float = -0.7
const VIEW_PITCH: float = 0.25
const FLIER_PITCH: float = 0.8
## How much of the bounding sphere the frame takes (< 1: closer; boxes overestimate shapes).
const FILL: float = 0.8
## Camera field of view (degrees).
const FOV: float = 30.0

static var _cache: Dictionary[StringName, Texture2D] = {}

## Turning speed of the figure (rad/s; 0 keeps it still).
@export var spin: float = 0.0

## The entry shown, or null.
var entry: JournalEntry

var _stage: Node3D
var _figure: Node3D
var _camera: Camera3D
var _framed := AABB()


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	size = Vector2i(256, 256)
	msaa_3d = Viewport.MSAA_4X


func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-30.0), 0.0)
	key.light_energy = 1.1
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.35
	add_child(fill)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.current = true
	add_child(_camera)
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)


func _process(delta: float) -> void:
	if spin != 0.0 and _stage != null:
		_stage.rotate_y(spin * delta)


## Puts [param shown] on the stage (replacing any figure) and frames it.
func show_entry(shown: JournalEntry) -> void:
	entry = shown
	if _figure != null:
		_figure.queue_free()
		_figure = null
	_stage.rotation = Vector3.ZERO
	if shown == null:
		return
	_figure = figure_for(shown)
	_stage.add_child(_figure)
	_pose(_figure, shown)
	var flier := (
		shown.source
		in [JournalEntry.Source.BIRD, JournalEntry.Source.FLITTER, JournalEntry.Source.SOARER]
	)
	_frame(FLIER_PITCH if flier or shown.source == JournalEntry.Source.FIREFLY else VIEW_PITCH)


## Renders [param shown] once and returns it as a texture (cached per entry). A coroutine: call
## it with [code]await[/code].
func snapshot(shown: JournalEntry) -> Texture2D:
	if _cache.has(shown.id):
		return _cache[shown.id]
	show_entry(shown)
	var image: Image = null
	if DisplayServer.get_name() != "headless":  # headless never draws (nor signals a frame)
		for attempt in 4:  # a new studio's first render can come out empty: ask again
			render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			image = get_texture().get_image()
			if image != null and not image.is_invisible():
				break
	if image == null or image.is_empty():
		image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	_cache[shown.id] = texture
	return texture


## The box (in the stage's space) the figure on stage was framed by.
func framed_box() -> AABB:
	return _framed


## Forgets every cached portrait (tests; a change of quality could also use it).
static func clear_cache() -> void:
	_cache.clear()


## The cached portrait of entry [param id], or null.
static func cached(id: StringName) -> Texture2D:
	return _cache.get(id, null)


## A new node showing [param shown]'s animal, standing on its origin.
static func figure_for(shown: JournalEntry) -> Node3D:
	match shown.source:
		JournalEntry.Source.FAUNA:
			var species := (shown.animal as FaunaSpecies).animal
			var model: Node3D = species.model_scene.instantiate()
			model.scale = Vector3.ONE * species.model_scale
			model.rotation.y = deg_to_rad(species.model_yaw_degrees)
			var holder := Node3D.new()
			holder.add_child(model)
			return holder
		JournalEntry.Source.CRITTER:
			return _mesh_figure(ProceduralMeshes.critter((shown.animal as CritterKind).shape))
		JournalEntry.Source.FARM:
			var farm := shown.animal as FarmAnimalKind
			var animal: Node3D = farm.scene.instantiate()
			animal.scale = Vector3.ONE * farm.model_scale
			animal.rotation.y = deg_to_rad(farm.yaw_offset)
			var pen := Node3D.new()
			pen.add_child(animal)
			return pen
		JournalEntry.Source.BIRD:
			var palette := (shown.animal as BirdSettings).palette
			return _mesh_figure(
				ProceduralMeshes.bird(), palette[0] if palette.size() > 0 else Color.WHITE
			)
		JournalEntry.Source.SOARER:
			return _mesh_figure(ProceduralMeshes.bird(), (shown.animal as SoarerSettings).tint)
		JournalEntry.Source.FLITTER:
			var kind := shown.animal as FlitterKind
			var mesh := (
				ProceduralMeshes.dragonfly()
				if kind.shape == &"dragonfly"
				else ProceduralMeshes.butterfly()
			)
			return _mesh_figure(mesh, kind.palette[0] if kind.palette.size() > 0 else Color.WHITE)
	var firefly := _mesh_figure(ProceduralMeshes.firefly())
	var glow := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.0035
	bulb.height = 0.007
	glow.mesh = bulb
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_color = (shown.animal as SmallLifeSettings).firefly_color
	glow.material_override = lit
	glow.position = Vector3(0.0, 0.001, 0.013)  # the tip of the abdomen
	firefly.add_child(glow)
	return firefly


static func _mesh_figure(mesh: Mesh, tint: Color = Color.WHITE) -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = tint
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # wings are single triangles
	node.material_override = material
	return node


# Holds a fauna model still in its idle pose (the clip's first moments).
static func _pose(figure: Node3D, shown: JournalEntry) -> void:
	if shown.source != JournalEntry.Source.FAUNA and shown.source != JournalEntry.Source.FARM:
		return
	var players := figure.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	var clip: String
	if shown.source == JournalEntry.Source.FARM:
		clip = (shown.animal as FarmAnimalKind).idle_clip
	else:
		clip = (shown.animal as FaunaSpecies).animal.animations.get(&"idle", "Idle")
	for name in player.get_animation_list():
		if String(name).ends_with(clip):
			player.play(name)
			player.seek(0.3, true)
			player.pause()
			return


# Centres the figure on the stage's axis and places the camera so all of it fits.
func _frame(pitch: float) -> void:
	var box := _bounds(_figure, entry.source == JournalEntry.Source.FARM)
	if entry.source != JournalEntry.Source.FARM:
		var bones := _bounds(_figure, true)
		# A mesh whose data is not in its skeleton's space (e.g. re-exported from Blender)
		# reports a box far from its pose: frame it by its bones instead.
		if bones.size != Vector3.ZERO and box.size.length() > 5.0 * bones.size.length():
			box = bones
	_framed = box
	var centre := box.get_center()
	_figure.position -= Vector3(centre.x, 0.0, centre.z)
	var radius := maxf(box.size.length() * 0.5 * FILL, 0.005)
	var distance := radius / sin(deg_to_rad(FOV) * 0.5) * 1.05
	# From the figure towards the camera: in front (−Z, where animals face), a little to its
	# left and above.
	var towards := Vector3(sin(VIEW_YAW), 0.0, -cos(VIEW_YAW)) * cos(pitch)
	towards.y = sin(pitch)
	var target := Vector3(0.0, centre.y, 0.0)
	_camera.position = target + towards * distance
	_camera.look_at(target)
	_camera.near = maxf(distance - radius * 2.0, 0.001)
	_camera.far = distance + radius * 2.0


# Bounding box of every visual under [param root], in [param root]'s parent space. With
# [param by_bones] a rigged model is measured by its bones instead, with a margin: the farm
# models' skinned meshes report boxes far from their pose.
static func _bounds(root: Node3D, by_bones: bool = false) -> AABB:
	var out := AABB()
	var first := true
	var parent_inverse := root.get_parent_node_3d().global_transform.affine_inverse()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if by_bones and not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		for bone in skeleton.get_bone_count():
			var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			var at: Vector3 = parent_inverse * pose
			out = AABB(at, Vector3.ZERO) if first else out.expand(at)
			first = false
		var margin := out.size * 0.15
		out = out.grow(maxf(maxf(margin.x, margin.y), margin.z))
		out.position.y = minf(out.position.y, 0.0)  # down to the feet
		return out
	for node in [root] + root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual == null:
			continue
		var box: AABB = parent_inverse * visual.global_transform * visual.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
