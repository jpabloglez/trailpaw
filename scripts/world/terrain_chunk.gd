class_name TerrainChunk
extends Node3D
## One streamed terrain chunk: a mesh plus optional [HeightMapShape3D] collision, built on
## the main thread from [ChunkData]. Designed to be pooled: [method apply] reuses the same
## [ArrayMesh], array container and collision shape every time.
##
## Edible vegetation and drops ([method VegetationLibrary.food_for]) in LOD 0 get one pooled
## sphere each in a food [Area3D] on the [code]interactable[/code] layer, so the
## [Interactor] finds them; the chunk is their interaction provider. Eating one hides the
## instance (zero scale) until it regrows on the game clock.
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
## Radius of a food target sphere (m).
const FOOD_SHAPE_RADIUS: float = 0.3
## Height of the food target above the instance origin (m).
const FOOD_SHAPE_LIFT: float = 0.15
## Real seconds between regrowth checks while something is depleted.
const REGROW_CHECK_INTERVAL: float = 1.0
## Bits of a food key holding the instance index (the rest is the food slot).
const FOOD_INDEX_BITS: int = 16

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
var _food_area: FoodArea
var _food_sphere := SphereShape3D.new()
var _food_owners := PackedInt32Array()
var _owner_slot: Dictionary[int, int] = {}
var _food_positions := PackedVector3Array()
var _food_used: int = 0
var _food_keys := PackedInt32Array()
var _food_slots: Array[StringName] = []
var _food_definitions: Array[InteractionDefinition] = []
var _buffers: Dictionary[StringName, PackedFloat32Array] = {}
## Food id → {instance index → game minute it regrows at}.
var _depleted: Dictionary[StringName, Dictionary] = {}
var _since_regrow_check: float = 0.0

@onready var _mesh_instance: MeshInstance3D = %Mesh
@onready var _collision: CollisionShape3D = %Collision
@onready var _water: MeshInstance3D = %Water
@onready var _body: StaticBody3D = %Body


func _ready() -> void:
	_arrays.resize(Mesh.ARRAY_MAX)
	_mesh_instance.mesh = _mesh
	_collision.shape = _heightmap
	_collision.disabled = true
	_food_sphere.radius = FOOD_SHAPE_RADIUS
	_food_area = FoodArea.new(self)
	add_child(_food_area)
	set_process(false)


func _process(delta: float) -> void:
	_since_regrow_check += delta
	if _since_regrow_check >= REGROW_CHECK_INTERVAL:
		_since_regrow_check = 0.0
		regrow()


## Replaces the chunk's geometry, collision and vegetation with [param data]. Vegetation is
## drawn only when a [param library] is given. Food outside [param edible_kinds] (when not
## empty) gets no targets.
func apply(
	data: ChunkData,
	material: Material,
	library: VegetationLibrary = null,
	edible_kinds: Array[StringName] = []
) -> void:
	if data.coord != coord:
		_depleted.clear()  # a different chunk: its own (fresh) state
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
	_apply_food(data, library, edible_kinds)
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


## Number of active food targets.
func food_count() -> int:
	return _food_used


## Whether instance [param index] of food [param id] is eaten and not yet regrown.
func is_depleted(id: StringName, index: int) -> bool:
	return _depleted.has(id) and (_depleted[id] as Dictionary).has(index)


## The [param i]-th active food target (0 … [method food_count] − 1), or null.
func interaction_target(i: int) -> InteractionTarget:
	if i < 0 or i >= _food_used:
		return null
	var key := _food_keys[i]
	var slot := key >> FOOD_INDEX_BITS
	var position := to_global(_food_positions[i])
	return InteractionTarget.new(_food_definitions[slot], position, _food_area, key)


## Provider protocol (see [InteractionTarget]): the target of the food area's shape
## [param shape_index] (as reported by a shape cast).
func target_for_shape(shape_index: int) -> InteractionTarget:
	return interaction_target(_owner_slot.get(_food_area.shape_find_owner(shape_index), -1))


## Provider protocol: whether the food of [param key] is there to eat.
func is_target_available(key: int) -> bool:
	var slot := key >> FOOD_INDEX_BITS
	if slot >= _food_slots.size():
		return false
	return not is_depleted(_food_slots[slot], key & ((1 << FOOD_INDEX_BITS) - 1))


## Provider protocol: the food of [param key] was eaten — hide it until it regrows.
func consume_target(key: int) -> void:
	var slot := key >> FOOD_INDEX_BITS
	var definition := _food_definitions[slot]
	if definition.regrowth_minutes <= 0.0:
		return
	var id := _food_slots[slot]
	var index := key & ((1 << FOOD_INDEX_BITS) - 1)
	if not _depleted.has(id):
		_depleted[id] = {}
	(_depleted[id] as Dictionary)[index] = GameState.game_minutes + definition.regrowth_minutes
	_show_instance(id, index, false)
	set_process(true)


## Brings back every depleted food whose regrowth time has passed.
func regrow() -> void:
	var now := GameState.game_minutes
	for id: StringName in _depleted.keys():
		var entries: Dictionary = _depleted[id]
		for index: int in entries.keys():
			if now >= float(entries[index]):
				entries.erase(index)
				_show_instance(id, index, true)
		if entries.is_empty():
			_depleted.erase(id)
	if _depleted.is_empty():
		set_process(false)


## Clears state so the node can go back to a pool. Keeps the mesh/shape objects for reuse.
func reset() -> void:
	visible = false
	_collision.disabled = true
	_water.visible = false
	lod = -1
	_disable_food(0)
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


## One target sphere per edible instance (LOD 0 only), then re-hides what is still depleted.
func _apply_food(
	data: ChunkData, library: VegetationLibrary, edible_kinds: Array[StringName]
) -> void:
	var used := 0
	_food_slots.clear()
	_food_definitions.clear()
	_buffers.clear()
	# Shapes are shape owners of one area (no nodes). Moving them inside the physics space
	# costs ~45 µs each; out of the tree they are registered once when the area comes back.
	remove_child(_food_area)
	if library != null and data.lod == 0:
		for id: StringName in data.vegetation:
			var definition := library.food_for(id)
			if definition == null:
				continue
			if not edible_kinds.is_empty() and not edible_kinds.has(definition.food_kind):
				continue
			var slot := _food_slots.size()
			_food_slots.append(id)
			_food_definitions.append(definition)
			var buffer: PackedFloat32Array = data.vegetation[id]
			_buffers[id] = buffer
			var stride := VegetationScatterer.FLOATS_PER_INSTANCE
			for index in buffer.size() / stride:
				var o := index * stride
				var owner := _food_owner(used)
				var position := Vector3(
					buffer[o + 3], buffer[o + 7] + FOOD_SHAPE_LIFT, buffer[o + 11]
				)
				_food_area.shape_owner_set_transform(owner, Transform3D(Basis.IDENTITY, position))
				_food_area.shape_owner_set_disabled(owner, false)
				if used >= _food_keys.size():
					_food_keys.resize(used + 1)
					_food_positions.resize(used + 1)
				_food_positions[used] = position
				_food_keys[used] = (slot << FOOD_INDEX_BITS) | index
				used += 1
	_disable_food(used)
	add_child(_food_area)
	for id: StringName in _depleted:
		for index: int in _depleted[id] as Dictionary:
			_show_instance(id, index, false)
	set_process(not _depleted.is_empty())


func _food_owner(index: int) -> int:
	if index < _food_owners.size():
		return _food_owners[index]
	var owner := _food_area.create_shape_owner(_food_area)
	_food_area.shape_owner_add_shape(owner, _food_sphere)
	_food_owners.append(owner)
	_owner_slot[owner] = index
	return owner


func _disable_food(from: int) -> void:
	for i in range(from, _food_owners.size()):
		_food_area.shape_owner_set_disabled(_food_owners[i], true)
	_food_used = from


## Shows or hides one instance of food [param id] and toggles its target shape.
func _show_instance(id: StringName, index: int, show: bool) -> void:
	var node: MultiMeshInstance3D = _vegetation.get(id)
	var buffer: PackedFloat32Array = _buffers.get(id, PackedFloat32Array())
	var o := index * VegetationScatterer.FLOATS_PER_INSTANCE
	if node == null or o + 11 >= buffer.size():
		return
	var origin := Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11])
	var basis := Basis(
		Vector3(buffer[o], buffer[o + 4], buffer[o + 8]),
		Vector3(buffer[o + 1], buffer[o + 5], buffer[o + 9]),
		Vector3(buffer[o + 2], buffer[o + 6], buffer[o + 10])
	)
	if not show:
		basis = Basis.from_scale(Vector3.ZERO)
	node.multimesh.set_instance_transform(index, Transform3D(basis, origin))
	var slot := _food_slots.find(id)
	var key := (slot << FOOD_INDEX_BITS) | index
	for i in _food_used:
		if _food_keys[i] == key:
			_food_area.shape_owner_set_disabled(_food_owners[i], not show)
			break
