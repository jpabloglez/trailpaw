class_name VegetationLibrary
extends RefCounted
## Meshes and render settings for every [VegetationType] in a biome table, extracted once on
## the main thread and shared by all chunks' MultiMeshes (one mesh resource per type). Each
## surface gets a foliage [ShaderMaterial] (wind sway) with the imported colour, optionally
## recoloured by a [VegetationPalette].

## Foliage shader used for every vegetation surface.
const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage.gdshader")
## Draw distance cap of drops (small props).
const DROP_RANGE: float = 45.0

var _meshes: Dictionary[StringName, Mesh] = {}
var _ranges: Dictionary[StringName, float] = {}
var _shadows: Dictionary[StringName, bool] = {}
var _collision: Dictionary[StringName, Vector2] = {}
var _sway: Dictionary[StringName, float] = {}
var _interactions: Dictionary[StringName, InteractionDefinition] = {}
var _drops: Array[StringName] = []
var _shade: Dictionary[StringName, float] = {}


func _init(table: BiomeTable, palette: VegetationPalette = null) -> void:
	for biome in table.biomes:
		for entry in biome.vegetation:
			var type := entry.type
			if _meshes.has(type.id):
				continue
			if type.procedural_shape != &"":
				_meshes[type.id] = _procedural_foliage(type)
			else:
				var root := type.scene.instantiate()
				var mesh_instance := root.find_children("*", "MeshInstance3D", true, false)[0]
				_meshes[type.id] = _foliage_mesh(
					(mesh_instance as MeshInstance3D).mesh, type, palette
				)
				root.free()
			_sway[type.id] = type.sway
			_ranges[type.id] = type.visibility_range
			# Small near-only plants skip shadows: many instances, little visual gain.
			_shadows[type.id] = not type.near_only
			if type.has_collision():
				_collision[type.id] = Vector2(type.collision_radius, type.collision_height)
			if type.shade_radius > 0.0:
				_shade[type.id] = type.shade_radius
			if type.interaction != null:
				_interactions[type.id] = type.interaction
			if type.drop != null:
				_add_drop(type.drop, type.visibility_range)


## Mesh shared by every instance of type [param id].
func mesh_for(id: StringName) -> Mesh:
	return _meshes.get(id)


## Draw distance of type [param id] (m).
func visibility_range(id: StringName) -> float:
	return _ranges.get(id, 0.0)


## Whether instances of type [param id] cast shadows.
func casts_shadows(id: StringName) -> bool:
	return _shadows.get(id, false)


## Collision cylinder (radius, height) in model units for type [param id]; zero if none.
func collision_for(id: StringName) -> Vector2:
	return _collision.get(id, Vector2.ZERO)


## Type ids known to the library.
func ids() -> Array[StringName]:
	return _meshes.keys()


## Shade radius of type [param id] in model units (0 = none).
func shade_for(id: StringName) -> float:
	return _shade.get(id, 0.0)


## Ids of the drops (props derived from other types: plain material, no wind).
func drop_ids() -> Array[StringName]:
	return _drops


## What interacting with an instance of type (or drop) [param id] does, or null.
func interaction_for(id: StringName) -> InteractionDefinition:
	return _interactions.get(id)


## Sway multiplier of type [param id].
func sway_for(id: StringName) -> float:
	return _sway.get(id, 0.0)


## Mesh for [param drop] ([ProceduralMeshes], 1 m across) with a plain material.
static func drop_mesh(drop: VegetationDrop) -> ArrayMesh:
	var shape := &"berry_cluster" if drop.shape == VegetationDrop.Shape.BERRY_CLUSTER else &"fruit"
	var mesh := ProceduralMeshes.build(shape)
	var material := StandardMaterial3D.new()
	material.albedo_color = drop.color
	material.roughness = 0.55
	mesh.surface_set_material(0, material)
	return mesh


## Copy of [param source] whose surfaces use foliage materials.
static func _foliage_mesh(source: Mesh, type: VegetationType, palette: VegetationPalette) -> Mesh:
	var mesh := source.duplicate() as Mesh
	var height := maxf(source.get_aabb().end.y, 0.01)
	for s in mesh.get_surface_count():
		var original := source.surface_get_material(s) as BaseMaterial3D
		var color := original.albedo_color if original != null else Color.WHITE
		if palette != null and original != null and palette.colors.has(original.resource_name):
			color = palette.colors[original.resource_name]
		var mat := ShaderMaterial.new()
		mat.shader = FOLIAGE_SHADER
		mat.resource_name = original.resource_name if original != null else "foliage"
		mat.set_shader_parameter("albedo", color)
		mat.set_shader_parameter("sway", type.sway)
		mat.set_shader_parameter("model_height", height)
		mesh.surface_set_material(s, mat)
	return mesh


func _add_drop(drop: VegetationDrop, parent_range: float) -> void:
	_meshes[drop.id] = drop_mesh(drop)
	_drops.append(drop.id)
	_ranges[drop.id] = minf(parent_range, DROP_RANGE)
	_shadows[drop.id] = false
	_sway[drop.id] = 0.0
	if drop.interaction != null:
		_interactions[drop.id] = drop.interaction


## A code-built mesh ([ProceduralMeshes]) with the foliage shader in the type's colour.
static func _procedural_foliage(type: VegetationType) -> Mesh:
	var mesh := ProceduralMeshes.build(type.procedural_shape)
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	mat.resource_name = String(type.procedural_shape)
	mat.set_shader_parameter("albedo", type.procedural_color)
	mat.set_shader_parameter("sway", type.sway)
	mat.set_shader_parameter("model_height", maxf(mesh.get_aabb().end.y, 0.01))
	mat.set_shader_parameter("vertex_colors", ProceduralMeshes.COLOURED.has(type.procedural_shape))
	mesh.surface_set_material(0, mat)
	return mesh
