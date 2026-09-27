class_name TerrainChunk
extends Node3D
## One streamed terrain chunk: a mesh plus optional [HeightMapShape3D] collision, built on
## the main thread from [ChunkData]. Designed to be pooled: [method apply] reuses the same
## [ArrayMesh], array container and collision shape every time.
##
## The chunk's origin is its corner; [code]WorldStreamer[/code] positions it relative to
## the floating origin.
## [br][br]
## Budget (main thread): one [method ArrayMesh.add_surface_from_arrays] plus, for LOD 0,
## one height-map upload. Measured on the target GTX 1050 (WSL, gl_compatibility): mesh
## upload ≈ 0.33 ms steady (first upload ≈ 4 ms: one-off material warm-up), height map
## ≈ 0.04 ms. No per-call allocations besides what the engine does internally.

## Surface format flag: CUSTOM0 carries palette colour B as RGBA8.
const CUSTOM0_FORMAT: int = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

## Grid coordinate of the data currently applied (absolute).
var coord: Vector2i = Vector2i.ZERO
## LOD of the data currently applied, or -1 when empty.
var lod: int = -1

var _border := PackedVector3Array()
var _mesh := ArrayMesh.new()
var _arrays: Array = []
var _heightmap := HeightMapShape3D.new()

@onready var _mesh_instance: MeshInstance3D = %Mesh
@onready var _collision: CollisionShape3D = %Collision


func _ready() -> void:
	_arrays.resize(Mesh.ARRAY_MAX)
	_mesh_instance.mesh = _mesh
	_collision.shape = _heightmap
	_collision.disabled = true


## Replaces the chunk's geometry and collision with [param data].
func apply(data: ChunkData, material: Material) -> void:
	coord = data.coord
	lod = data.lod
	_border = data.border
	_arrays[Mesh.ARRAY_VERTEX] = data.vertices
	_arrays[Mesh.ARRAY_NORMAL] = data.normals
	_arrays[Mesh.ARRAY_TEX_UV] = data.uvs
	_arrays[Mesh.ARRAY_COLOR] = data.colors if not data.colors.is_empty() else null
	_arrays[Mesh.ARRAY_CUSTOM0] = data.custom0 if not data.custom0.is_empty() else null
	_arrays[Mesh.ARRAY_INDEX] = data.indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays, [], {}, CUSTOM0_FORMAT)
	_mesh.surface_set_material(0, material)
	if data.collision_heights.is_empty():
		_collision.disabled = true
	else:
		var size := data.step * float(data.resolution - 1)
		_heightmap.map_width = data.resolution
		_heightmap.map_depth = data.resolution
		_heightmap.map_data = data.collision_heights
		# HeightMapShape3D is centred on its origin.
		_collision.position = Vector3(size * 0.5, 0.0, size * 0.5)
		_collision.disabled = false
	visible = true


## Closed outline of the chunk's surface border in local space (for debug gizmos).
func border_outline() -> PackedVector3Array:
	return _border


## Whether this chunk currently has active collision.
func has_collision() -> bool:
	return not _collision.disabled


## Clears state so the node can go back to a pool. Keeps the mesh/shape objects for reuse.
func reset() -> void:
	visible = false
	_collision.disabled = true
	lod = -1
