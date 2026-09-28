class_name TerrainChunk
extends Node3D
## One streamed terrain chunk: a mesh plus optional [HeightMapShape3D] collision, built on
## the main thread from [ChunkData]. Designed to be pooled: [method apply] reuses the same
## [ArrayMesh], array container and collision shape every time.
##
## The chunk's origin is its corner; [code]WorldStreamer[/code] positions it relative to
## the floating origin.
## [br][br]
## Budget (main thread): one [method ArrayMesh.add_surface_from_arrays], one buffer copy per
## vegetation type (MultiMeshes reused) plus, for LOD 0,
## one height-map upload. Measured on the target GTX 1050 (WSL, gl_compatibility): mesh
## upload ≈ 0.33 ms steady (first upload ≈ 4 ms: one-off material warm-up), height map
## ≈ 0.04 ms. No per-call allocations besides what the engine does internally.

## Fraction of a vegetation type's draw distance used to fade it out.
const FADE_MARGIN: float = 0.1

## Grid coordinate of the data currently applied (absolute).
var coord: Vector2i = Vector2i.ZERO
## LOD of the data currently applied, or -1 when empty.
var lod: int = -1
## Streamer generation of the data currently applied (see [method WorldStreamer.refresh]).
var generation: int = 0

var _border := PackedVector3Array()
var _mesh := ArrayMesh.new()
var _vegetation: Dictionary[StringName, MultiMeshInstance3D] = {}
var _obstacles: Array[CollisionShape3D] = []
var _obstacles_used: int = 0
var _arrays: Array = []
var _heightmap := HeightMapShape3D.new()

@onready var _mesh_instance: MeshInstance3D = %Mesh
@onready var _collision: CollisionShape3D = %Collision
@onready var _water: MeshInstance3D = %Water
@onready var _body: StaticBody3D = %Body


func _ready() -> void:
	_arrays.resize(Mesh.ARRAY_MAX)
	_mesh_instance.mesh = _mesh
	_collision.shape = _heightmap
	_collision.disabled = true


## Replaces the chunk's geometry, collision and vegetation with [param data]. Vegetation is
## drawn only when a [param library] is given.
func apply(data: ChunkData, material: Material, library: VegetationLibrary = null) -> void:
	coord = data.coord
	lod = data.lod
	_border = data.border
	_arrays[Mesh.ARRAY_VERTEX] = data.vertices
	_arrays[Mesh.ARRAY_NORMAL] = data.normals
	_arrays[Mesh.ARRAY_TEX_UV] = data.uvs
	_arrays[Mesh.ARRAY_COLOR] = data.colors if not data.colors.is_empty() else null
	_arrays[Mesh.ARRAY_TEX_UV2] = data.uv2 if not data.uv2.is_empty() else null
	_arrays[Mesh.ARRAY_INDEX] = data.indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
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
	# Water: one shared 1×1 plane per chunk, scaled to the chunk (no per-chunk mesh).
	_water.visible = data.has_water()
	if _water.visible:
		var side := data.step * float(data.resolution - 1)
		_water.position = Vector3(side * 0.5, data.water_level, side * 0.5)
		_water.scale = Vector3(side, 1.0, side)
	_apply_vegetation(data, library)
	_apply_obstacles(data, library)
	visible = true


## Closed outline of the chunk's surface border in local space (for debug gizmos).
func border_outline() -> PackedVector3Array:
	return _border


## Number of visible vegetation instances of type [param id].
func vegetation_count(id: StringName) -> int:
	var node: MultiMeshInstance3D = _vegetation.get(id)
	return node.multimesh.instance_count if node != null and node.visible else 0


## The MultiMesh node drawing type [param id], or [code]null[/code].
func vegetation_node(id: StringName) -> MultiMeshInstance3D:
	return _vegetation.get(id)


## Number of active tree/rock collision shapes.
func obstacle_count() -> int:
	return _obstacles_used


## Whether this chunk currently shows a water plane.
func has_water() -> bool:
	return _water.visible


## Whether this chunk currently has active collision.
func has_collision() -> bool:
	return not _collision.disabled


## Clears state so the node can go back to a pool. Keeps the mesh/shape objects for reuse.
func reset() -> void:
	visible = false
	_collision.disabled = true
	_water.visible = false
	lod = -1
	for node: MultiMeshInstance3D in _vegetation.values():
		node.visible = false
	_disable_obstacles(0)


## One reused MultiMeshInstance3D per type: the buffer is copied as-is from the worker.
func _apply_vegetation(data: ChunkData, library: VegetationLibrary) -> void:
	for node: MultiMeshInstance3D in _vegetation.values():
		node.visible = false
	if library == null:
		return
	for id: StringName in data.vegetation:
		var buffer: PackedFloat32Array = data.vegetation[id]
		var node: MultiMeshInstance3D = _vegetation.get(id)
		if node == null:
			node = MultiMeshInstance3D.new()
			node.name = "Vegetation_" + String(id)
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = library.mesh_for(id)
			node.multimesh = multimesh
			node.visibility_range_end = library.visibility_range(id)
			# Dithered fade over the last 10 % (Forward+; Compatibility cuts instead).
			node.visibility_range_end_margin = library.visibility_range(id) * FADE_MARGIN
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			node.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if library.casts_shadows(id)
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
			add_child(node)
			_vegetation[id] = node
		var count := buffer.size() / VegetationScatterer.FLOATS_PER_INSTANCE
		if node.multimesh.instance_count != count:
			node.multimesh.instance_count = count
		node.multimesh.buffer = buffer
		node.visible = true


## Upright collision cylinders for trees and large rocks, in LOD 0 chunks only (the player
## never walks on coarse chunks). Shape nodes and their CylinderShape3Ds are pooled.
func _apply_obstacles(data: ChunkData, library: VegetationLibrary) -> void:
	var used := 0
	if library != null and data.lod == 0:
		for id: StringName in data.vegetation:
			var size := library.collision_for(id)
			if size.x <= 0.0:
				continue
			var buffer: PackedFloat32Array = data.vegetation[id]
			var stride := VegetationScatterer.FLOATS_PER_INSTANCE
			for o in range(0, buffer.size(), stride):
				var scale := Vector3(buffer[o], buffer[o + 4], buffer[o + 8]).length()
				var node := _obstacle(used)
				var cylinder := node.shape as CylinderShape3D
				cylinder.radius = size.x * scale
				cylinder.height = size.y * scale
				node.position = Vector3(
					buffer[o + 3], buffer[o + 7] + cylinder.height * 0.5, buffer[o + 11]
				)
				node.disabled = false
				used += 1
	_disable_obstacles(used)


func _obstacle(index: int) -> CollisionShape3D:
	if index < _obstacles.size():
		return _obstacles[index]
	var node := CollisionShape3D.new()
	node.shape = CylinderShape3D.new()
	_body.add_child(node)
	_obstacles.append(node)
	return node


func _disable_obstacles(from: int) -> void:
	for i in range(from, _obstacles.size()):
		_obstacles[i].disabled = true
	_obstacles_used = from
