class_name TerrainChunk
extends Node3D
## One streamed terrain chunk: a mesh plus optional [HeightMapShape3D] collision, built on
## the main thread from [ChunkData]. Designed to be pooled: [method apply] reuses the same
## [ArrayMesh], array container and collision shape every time.
##
## Depleted food lives in the shared [member delta_store], so it survives unloading.
##
## Edible vegetation and drops, and props to rest by
## ([method VegetationLibrary.interaction_for]), in LOD 0 get one pooled sphere each in a
## [FoodArea] on the [code]interactable[/code] layer, so the [Interactor] finds them; the chunk
## is their interaction provider. Eating hides the instance (zero scale) until it regrows on the
## game clock.
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
## Vegetation that grows at the water ([method spots] [code]&"water_plant"[/code]).
const WATER_PLANTS: Array[StringName] = [&"reeds", &"cattails", &"water_lily", &"water_lily_flower"]

## Grid coordinate of the data currently applied (absolute).
var coord: Vector2i = Vector2i.ZERO
## LOD of the data currently applied, or -1 when empty.
var lod: int = -1
## Streamer generation of the data currently applied (see [method WorldStreamer.refresh]).
var generation: int = 0
## Depleted resources of every chunk (shared through the [WorldStreamer]; a private store when
## the chunk is used alone, e.g. in tests).
var delta_store: ChunkDeltaStore = ChunkDeltaStore.new()

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
var _since_regrow_check: float = 0.0
## Food id → {instance index → true} for instances drawn hidden (zero scale) now.
var _hidden: Dictionary[StringName, Dictionary] = {}
var _shade_buffers: Array[PackedFloat32Array] = []
var _shade_radii := PackedFloat32Array()
var _shade_heights := PackedFloat32Array()
var _flower_buffers: Array[PackedFloat32Array] = []
var _water_plant_buffers: Array[PackedFloat32Array] = []

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
	_apply_shade(data, library)
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


## Whether [param local_position] (chunk-local) lies in the shade of a tree: within the tree's
## shade radius × its scale, horizontally.
## [br][br]
## Budget: O(trees in the chunk), a few float ops each; called a few times per second at most.
func is_shaded(local_position: Vector3) -> bool:
	var stride := VegetationScatterer.FLOATS_PER_INSTANCE
	for t in _shade_buffers.size():
		var buffer := _shade_buffers[t]
		var radius := _shade_radii[t]
		for o in range(0, buffer.size(), stride):
			var scale := Vector3(buffer[o], buffer[o + 4], buffer[o + 8]).length()
			var dx := local_position.x - buffer[o + 3]
			var dz := local_position.z - buffer[o + 11]
			var reach := radius * scale
			if dx * dx + dz * dz <= reach * reach:
				return true
	return false


## Appends spots of [param kind] in this chunk (global positions) to [param out]:
## [code]&"tree_top"[/code], the top of every tree's crown (birds perch there),
## [code]&"flower"[/code], every flower (butterflies visit them), or
## [code]&"water_plant"[/code], every reed, cattail and water lily (dragonflies dart over them).
## [br][br]
## Budget: O(trees, flowers or water plants in the chunk); called when a flock picks a perch,
## or a couple of times per second for flowers and water plants.
func spots(kind: StringName, out: PackedVector3Array) -> void:
	var stride := VegetationScatterer.FLOATS_PER_INSTANCE
	if kind == &"flower" or kind == &"water_plant":
		for buffer in _flower_buffers if kind == &"flower" else _water_plant_buffers:
			for o in range(0, buffer.size(), stride):
				out.append(to_global(Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11])))
		return
	for t in _shade_buffers.size():
		var buffer := _shade_buffers[t]
		for o in range(0, buffer.size(), stride):
			var scale := Vector3(buffer[o + 1], buffer[o + 5], buffer[o + 9]).length()
			var top := Vector3(
				buffer[o + 3], buffer[o + 7] + _shade_heights[t] * scale * 0.92, buffer[o + 11]
			)
			out.append(to_global(top))


## Whether instance [param index] of food [param id] is drawn hidden (eaten) right now.
func is_hidden(id: StringName, index: int) -> bool:
	return _hidden.has(id) and (_hidden[id] as Dictionary).has(index)


## Whether instance [param index] of food [param id] is eaten and not yet regrown. It counts as
## depleted until [method regrow] shows it again, so it is never edible while invisible.
func is_depleted(id: StringName, index: int) -> bool:
	var ids: Dictionary = delta_store.entries_for(coord).get(id, {})
	return ids.has(index)


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
	delta_store.deplete(coord, id, index, GameState.game_minutes + definition.regrowth_minutes)
	_show_instance(id, index, false)
	set_process(true)


## Brings back every depleted food whose regrowth time has passed.
func regrow() -> void:
	for entry: Array in delta_store.take_regrown(coord, GameState.game_minutes):
		_show_instance(entry[0], entry[1], true)
	if delta_store.entries_for(coord).is_empty():
		set_process(false)


## Pre-creates up to [param food] food target shapes and [param obstacles] obstacle shapes,
## disabled, so a later [method apply] up to those counts never creates physics objects (the
## first apply of a cold node used to cost up to ~7 ms). Creates at most [param max_new] shapes
## per call so the work can be spread over frames; returns whether the reserve is complete.
## [br][br]
## Budget: ≈ 40 µs per new shape; nothing once the reserve is complete.
func reserve(food: int, obstacles: int, max_new: int = 1 << 30) -> bool:
	var budget := max_new
	if _food_owners.size() < food and budget > 0:
		remove_child(_food_area)  # shape owners register in one go when the area comes back
		while _food_owners.size() < food and budget > 0:
			var owner := _food_owner(_food_owners.size())
			_food_area.shape_owner_set_disabled(owner, true)
			budget -= 1
		add_child(_food_area)
	if _obstacles.size() < obstacles and budget > 0:
		var space := _leave_space()
		while _obstacles.size() < obstacles and budget > 0:
			_obstacle(_obstacles.size()).disabled = true
			budget -= 1
		_return_to_space(space)
	return _food_owners.size() >= food and _obstacles.size() >= obstacles


## Shapes created so far: [food targets, obstacles] (tests and tools).
func reserved() -> Vector2i:
	return Vector2i(_food_owners.size(), _obstacles.size())


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
	_flower_buffers.clear()
	_water_plant_buffers.clear()
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
		if String(id).begins_with("flower"):
			_flower_buffers.append(buffer)  # a reference, not a copy
		elif WATER_PLANTS.has(id):
			_water_plant_buffers.append(buffer)
		var count := buffer.size() / VegetationScatterer.FLOATS_PER_INSTANCE
		if node.multimesh.instance_count != count:
			node.multimesh.instance_count = count
		node.multimesh.buffer = buffer
		node.visible = true


## Upright collision cylinders for trees and large rocks, in LOD 0 chunks only (the player
## never walks on coarse chunks). Shape nodes and their CylinderShape3Ds are pooled.
func _apply_obstacles(data: ChunkData, library: VegetationLibrary) -> void:
	# Moving shapes of a body inside the physics space costs ~40 µs each (2 ms for a wooded
	# chunk); out of the space they are registered once when the body goes back.
	var space := _leave_space()
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
	_return_to_space(space)


# Takes the body (terrain + obstacles) out of the physics space, so moving its shapes skips the
# broadphase; returns the space to give back to [method _return_to_space].
func _leave_space() -> RID:
	var space := PhysicsServer3D.body_get_space(_body.get_rid())
	PhysicsServer3D.body_set_space(_body.get_rid(), RID())
	return space


func _return_to_space(space: RID) -> void:
	PhysicsServer3D.body_set_space(_body.get_rid(), space)


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
	_hidden.clear()  # fresh buffers draw every instance
	# Shapes are shape owners of one area (no nodes). Moving them inside the physics space
	# costs ~45 µs each; out of the tree they are registered once when the area comes back.
	remove_child(_food_area)
	if library != null and data.lod == 0:
		for id: StringName in data.vegetation:
			var definition := library.interaction_for(id)
			if definition == null:
				continue
			var food := definition.food_kind
			if food != &"" and not edible_kinds.is_empty() and not edible_kinds.has(food):
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
	# Regrown while unloaded: drop those entries; the rest stay hidden.
	delta_store.take_regrown(coord, GameState.game_minutes)
	var depleted := delta_store.entries_for(coord)
	for id: StringName in depleted:
		for index: int in depleted[id] as Dictionary:
			_show_instance(id, index, false)
	set_process(not depleted.is_empty())


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
	if show:
		if _hidden.has(id):
			(_hidden[id] as Dictionary).erase(index)
	else:
		if not _hidden.has(id):
			_hidden[id] = {}
		(_hidden[id] as Dictionary)[index] = true
	var slot := _food_slots.find(id)
	var key := (slot << FOOD_INDEX_BITS) | index
	for i in _food_used:
		if _food_keys[i] == key:
			_food_area.shape_owner_set_disabled(_food_owners[i], not show)
			break


func _apply_shade(data: ChunkData, library: VegetationLibrary) -> void:
	_shade_buffers.clear()
	_shade_radii.clear()
	_shade_heights.clear()
	if library == null:
		return
	for id: StringName in data.vegetation:
		var radius := library.shade_for(id)
		if radius > 0.0:
			_shade_buffers.append(data.vegetation[id])
			_shade_radii.append(radius)
			var mesh := library.mesh_for(id)
			_shade_heights.append(mesh.get_aabb().end.y if mesh != null else 3.0)
