class_name HamletPantry
extends Area3D
## The food of one hamlet: cabbages in its vegetable patch and eggs in the hens' nest, each an
## [InteractionTarget] on the [code]interactable[/code] layer (one sphere shape per item). Eaten
## items stay gone until they regrow ([member InteractionDefinition.regrowth_minutes], a day),
## remembered in the world's [ChunkDeltaStore] so it survives the hamlet being freed and saves.
## Made by [HamletFood].

## Where eaten items are remembered (the world's chunk deltas).
var deltas: ChunkDeltaStore

var _definitions: Array[InteractionDefinition] = []
var _ids: Array[StringName] = []  # delta ids
var _coords: Array[Vector2i] = []  # chunk of each item (absolute)
var _meshes: Array[Node3D] = []


func _ready() -> void:
	collision_layer = Interactable.LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


## Adds an item: [param mesh] (a child already placed), what eating it does, and the absolute
## chunk it lies in.
func add_item(mesh: Node3D, definition: InteractionDefinition, chunk: Vector2i) -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	add_child(shape)
	shape.global_position = mesh.global_position + Vector3.UP * 0.15
	_meshes.append(mesh)
	_definitions.append(definition)
	_ids.append(StringName("hamlet_" + String(definition.id)))
	_coords.append(chunk)


## Items in this pantry.
func count() -> int:
	return _meshes.size()


## Where item [param key] is (global).
func position_of(key: int) -> Vector3:
	return _meshes[key].global_position


## Its definition.
func definition_of(key: int) -> InteractionDefinition:
	return _definitions[key]


## Shows the items that are there and hides the eaten ones.
func refresh() -> void:
	for key in _meshes.size():
		_meshes[key].visible = is_target_available(key)


## The target of shape [param shape_index] (one shape per item, in order).
func interaction_target(shape_index: int) -> InteractionTarget:
	if shape_index < 0 or shape_index >= _meshes.size():
		return null
	return InteractionTarget.new(
		_definitions[shape_index], position_of(shape_index), self, shape_index
	)


## Provider protocol: whether item [param key] is there (not eaten, or regrown).
func is_target_available(key: int) -> bool:
	if key < 0 or key >= _meshes.size():
		return false
	return (
		deltas == null
		or not deltas.is_depleted(_coords[key], _ids[key], key, GameState.game_minutes)
	)


## Provider protocol: item [param key] was eaten.
func consume_target(key: int) -> void:
	if deltas != null:
		var regrow := GameState.game_minutes + _definitions[key].regrowth_minutes
		deltas.deplete(_coords[key], _ids[key], key, regrow)
	_meshes[key].visible = false
