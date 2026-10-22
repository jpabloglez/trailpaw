class_name BeaverLodges
extends Node3D
## The beavers' lodges (Phase 19): a mound of sticks on the waterline at the centre of each
## beaver group, kept by the [CritterSystem] that rolls the group (one lodge per group, added and
## dropped with its chunk). Drawn with one [MultiMeshInstance3D]; each lodge has a cylinder
## collider on the world layer so the fox walks and swims round it. Positions are local and
## follow floating-origin rebases.
## [br][br]
## Budget: a handful of lodges near the fox; the MultiMesh is rewritten only when one is added
## or dropped.

## Radius and height of a lodge's collider (m).
const RADIUS: float = 1.4
const HEIGHT: float = 3.0

var _chunks: Array[Vector2i] = []
var _places := PackedVector3Array()
var _yaws := PackedFloat32Array()
var _bodies: Array[StaticBody3D] = []
var _view: MultiMeshInstance3D


func _ready() -> void:
	_view = MultiMeshInstance3D.new()
	_view.name = "Lodges"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = ProceduralMeshes.lodge()
	_view.multimesh = multimesh
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.95
	_view.material_override = look
	add_child(_view)
	EventBus.origin_shifted.connect(_on_origin_shifted)


## Adds a lodge of chunk [param chunk] at local [param at] (on the ground), turned [param yaw].
func add(chunk: Vector2i, at: Vector3, yaw: float) -> void:
	_chunks.append(chunk)
	_places.append(at)
	_yaws.append(yaw)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = HEIGHT
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)
	body.position = at + Vector3.UP * HEIGHT * 0.25
	_bodies.append(body)
	_redraw()


## Drops the lodges of chunks not in [param available] (chunk → true).
func keep_only(available: Dictionary) -> void:
	var dropped := false
	for i in range(_chunks.size() - 1, -1, -1):
		if available.has(_chunks[i]):
			continue
		_bodies[i].queue_free()
		_bodies.remove_at(i)
		_chunks.remove_at(i)
		_places.remove_at(i)
		_yaws.remove_at(i)
		dropped = true
	if dropped:
		_redraw()


## Lodges standing now.
func count() -> int:
	return _places.size()


## Where lodge [param i] stands (local).
func place_of(i: int) -> Vector3:
	return _places[i]


## The collider of lodge [param i].
func body_of(i: int) -> StaticBody3D:
	return _bodies[i]


func _redraw() -> void:
	if _view == null:
		return
	var multimesh := _view.multimesh
	multimesh.instance_count = _places.size()
	for i in _places.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _yaws[i]), _places[i]))


func _on_origin_shifted(offset: Vector3) -> void:
	for i in _places.size():
		_places[i] -= offset
		_bodies[i].position -= offset
	_redraw()
