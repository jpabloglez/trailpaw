class_name VegetationLibrary
extends RefCounted
## Meshes and render settings for every [VegetationType] in a biome table, extracted once on
## the main thread and shared by all chunks' MultiMeshes (one mesh resource per type).

var _meshes: Dictionary[StringName, Mesh] = {}
var _ranges: Dictionary[StringName, float] = {}
var _shadows: Dictionary[StringName, bool] = {}
var _collision: Dictionary[StringName, Vector2] = {}


func _init(table: BiomeTable) -> void:
	for biome in table.biomes:
		for entry in biome.vegetation:
			var type := entry.type
			if _meshes.has(type.id):
				continue
			var root := type.scene.instantiate()
			var mesh_instance := root.find_children("*", "MeshInstance3D", true, false)[0]
			_meshes[type.id] = (mesh_instance as MeshInstance3D).mesh
			root.free()
			_ranges[type.id] = type.visibility_range
			# Small near-only plants skip shadows: many instances, little visual gain.
			_shadows[type.id] = not type.near_only
			if type.has_collision():
				_collision[type.id] = Vector2(type.collision_radius, type.collision_height)


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
