class_name HeadLook
extends Node3D
## Turns the player's head towards what is interesting: the [Interactor]'s current target, else
## the nearest animal within [member HeadLookSettings.animal_range], else straight ahead. A
## [LookAtModifier3D] on the species' head bone does the turning, within the yaw/pitch limits;
## this node is its smoothed target. Off (influence fades) in the air, swimming and when running.
## [br][br]
## Budget: one pass over the fauna group (≤ 10 animals) per frame and a few vector ops.

## What to look at and how far.
@export var settings: HeadLookSettings
## The animal body.
@export var body: CharacterBody3D
## Its movement (speed, grounded, swimming).
@export var movement: MovementComponent
## The model (holds the species' skeleton).
@export var model_root: Node3D
## Gives the current interaction target (optional).
@export var interactor: Interactor

var _look: LookAtModifier3D
var _head := -1
var _skeleton: Skeleton3D


func _ready() -> void:
	top_level = true
	add_to_group(FloatingOrigin.SHIFTABLE_GROUP)


func _process(delta: float) -> void:
	if _look == null and not _setup():
		return
	var rate := clampf(delta * settings.smoothing, 0.0, 1.0)
	_look.influence = lerpf(_look.influence, 1.0 if looking() else 0.0, rate)
	global_position = global_position.lerp(focus(), rate)


## Whether the head is turning now (on the ground, not swimming, not running).
func looking() -> bool:
	if movement == null or movement.species == null:
		return false
	if movement.swimming or not movement.is_grounded():
		return false
	return movement.horizontal_speed() <= movement.species.trot_speed * settings.max_speed_factor


## Where the head wants to look now (world).
func focus() -> Vector3:
	if interactor != null:
		var target := interactor.current_target()
		if target != null:
			return target.position
	var head := _head_position()
	var best := Vector3.INF
	var best_distance := settings.animal_range
	for node in get_tree().get_nodes_in_group(FaunaAgent.GROUP):
		var animal := node as Node3D
		if animal == null or not animal.is_inside_tree():
			continue
		var distance := animal.global_position.distance_to(head)
		if distance < best_distance:
			best_distance = distance
			best = animal.global_position + Vector3.UP * 0.4
	if best != Vector3.INF:
		return best
	return head - body.global_basis.z * settings.ahead


## The look-at modifier (null until the model exists or when the species has no head bone).
func modifier() -> LookAtModifier3D:
	return _look


func _head_position() -> Vector3:
	if _skeleton == null or _head < 0:
		return body.global_position
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head).origin


func _setup() -> bool:
	if model_root == null or movement == null or movement.species == null:
		return false
	var bone_name := movement.species.head_bone
	if bone_name == "":
		set_process(false)
		return false
	var skeletons := model_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return false
	_skeleton = skeletons[0] as Skeleton3D
	_head = _skeleton.find_bone(bone_name)
	if _head < 0:
		set_process(false)
		return false
	var rest := _skeleton.global_transform * _skeleton.get_bone_global_rest(_head)
	_look = LookAtModifier3D.new()
	_look.name = "HeadLook"
	_look.bone = _head
	# Which local axes of the head point forward and up in the rest pose.
	_look.forward_axis = _bone_axis(rest.basis, -body.global_basis.z)
	_look.primary_rotation_axis = _vector_axis(rest.basis, body.global_basis.y)
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(settings.yaw_range)
	_look.secondary_limit_angle = deg_to_rad(settings.pitch_range)
	_look.influence = 0.0
	_skeleton.add_child(_look)
	global_position = focus()
	_look.target_node = _look.get_path_to(self)
	return true


# The bone axis (±X/±Y/±Z) closest to world direction [param world] in the rest pose.
static func _bone_axis(basis: Basis, world: Vector3) -> SkeletonModifier3D.BoneAxis:
	var local := (basis.orthonormalized().inverse() * world).normalized()
	var axis := local.abs().max_axis_index()
	var negative := local[axis] < 0.0
	match axis:
		Vector3.AXIS_X:
			return (
				SkeletonModifier3D.BONE_AXIS_MINUS_X
				if negative
				else SkeletonModifier3D.BONE_AXIS_PLUS_X
			)
		Vector3.AXIS_Y:
			return (
				SkeletonModifier3D.BONE_AXIS_MINUS_Y
				if negative
				else SkeletonModifier3D.BONE_AXIS_PLUS_Y
			)
	return SkeletonModifier3D.BONE_AXIS_MINUS_Z if negative else SkeletonModifier3D.BONE_AXIS_PLUS_Z


static func _vector_axis(basis: Basis, world: Vector3) -> Vector3.Axis:
	var local := (basis.orthonormalized().inverse() * world).normalized()
	return local.abs().max_axis_index() as Vector3.Axis
