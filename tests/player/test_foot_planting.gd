## Tests for foot planting ([FootPlanter], [LegIK]) and head-look ([HeadLook]) on the fox. Poses
## are read in [signal Skeleton3D.skeleton_updated], the only place modifier results are visible.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const STEP: float = 0.08

var _gaps := PackedFloat32Array()
var _head_forward := Vector3.ZERO


func _box(size: Vector3, at: Vector3) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = at
	body.add_child(shape)
	add_child(body)


func _animal() -> Animal:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ground(animal: Animal, at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN)
	query.exclude = [animal.get_rid()]
	var hit := animal.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.position as Vector3).y if not hit.is_empty() else NAN


# Paw-to-ground gap of every leg after the modifiers, from the next skeleton update.
func _measure_gaps(animal: Animal, ik: LegIK) -> PackedFloat32Array:
	var skeleton := ik.get_skeleton()
	var grab := func() -> void:
		_gaps.clear()
		for i in ik.leg_count():
			var tip := ik.tip_now(i)
			_gaps.append(tip.y - _ground(animal, tip))
	skeleton.skeleton_updated.connect(grab)
	await get_tree().process_frame
	await get_tree().process_frame
	skeleton.skeleton_updated.disconnect(grab)
	return _gaps.duplicate()


func test_paws_reach_the_ground_on_a_step() -> void:
	_box(Vector3(10, 1, 10), Vector3(0, -0.5, 0))
	_box(Vector3(2, STEP, 0.9), Vector3(0, STEP * 0.5, -0.75))  # under the front paws only
	var animal := _animal()
	await _frames(60)
	var planter := animal.get_node("%FootPlanter") as FootPlanter
	var ik := planter.leg_ik()
	assert_object(ik).is_not_null()
	assert_int(ik.leg_count()).is_equal(4)
	var planted := await _measure_gaps(animal, ik)
	# Every paw ends up at the same small clearance above its own ground (the clip's).
	for gap in planted:
		assert_float(gap).is_between(-0.01, 0.04)
	# Without the IK the back paws hang in the air by the step's height.
	planter.set_physics_process(false)
	ik.influence = 0.0
	var hanging := await _measure_gaps(animal, ik)
	assert_float(hanging[2]).is_greater(planted[2] + STEP * 0.8)
	assert_float(hanging[3]).is_greater(planted[3] + STEP * 0.8)


func test_flat_ground_leaves_the_animation_alone() -> void:
	_box(Vector3(10, 1, 10), Vector3(0, -0.5, 0))
	var animal := _animal()
	await _frames(60)
	var ik := (animal.get_node("%FootPlanter") as FootPlanter).leg_ik()
	for offset in ik.offsets:
		assert_float(absf(offset)).is_less(0.005)


func test_no_planting_in_the_air_or_swimming() -> void:
	var animal := _animal()  # nothing under it: falling
	await _frames(30)
	var planter := animal.get_node("%FootPlanter") as FootPlanter
	assert_bool(planter.planting()).is_false()
	var ik := planter.leg_ik()
	if ik != null:
		assert_float(ik.influence).is_less(0.05)
	_box(Vector3(10, 1, 10), Vector3(0, -0.5, 0))
	animal.position = Vector3(0, 0.05, 0)
	await _frames(30)
	assert_bool(planter.planting()).is_true()
	animal.movement.swimming = true
	assert_bool(planter.planting()).is_false()
	animal.movement.swimming = false


# --- head look ------------------------------------------------------------------------------


func _measure_head(look: HeadLook) -> Vector3:
	var modifier := look.modifier()
	var skeleton := modifier.get_skeleton()
	var axis := _axis_vector(modifier.forward_axis)
	var grab := func() -> void:
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(modifier.bone)
		_head_forward = (pose.basis.orthonormalized() * axis).normalized()
	skeleton.skeleton_updated.connect(grab)
	await get_tree().process_frame
	await get_tree().process_frame
	skeleton.skeleton_updated.disconnect(grab)
	return _head_forward


static func _axis_vector(axis: SkeletonModifier3D.BoneAxis) -> Vector3:
	match axis:
		SkeletonModifier3D.BONE_AXIS_PLUS_X:
			return Vector3.RIGHT
		SkeletonModifier3D.BONE_AXIS_MINUS_X:
			return Vector3.LEFT
		SkeletonModifier3D.BONE_AXIS_PLUS_Y:
			return Vector3.UP
		SkeletonModifier3D.BONE_AXIS_MINUS_Y:
			return Vector3.DOWN
		SkeletonModifier3D.BONE_AXIS_PLUS_Z:
			return Vector3.BACK
	return Vector3.FORWARD


func _fauna_at(at: Vector3) -> Node3D:
	var stand_in: Node3D = auto_free(Node3D.new())
	stand_in.add_to_group(FaunaAgent.GROUP)
	add_child(stand_in)
	stand_in.global_position = at
	return stand_in


func test_the_head_turns_towards_a_nearby_animal() -> void:
	_box(Vector3(10, 1, 10), Vector3(0, -0.5, 0))
	var animal := _animal()
	await _frames(30)
	var look := animal.get_node("%HeadLook") as HeadLook
	var ahead := await _measure_head(look)
	assert_float(ahead.dot(-animal.global_basis.z)).is_greater(0.8)  # nothing around: ahead
	_fauna_at(animal.global_position + Vector3(2.5, 0.0, -1.5))  # front right
	await _frames(60)
	var turned := await _measure_head(look)
	var head := animal.global_position + Vector3.UP * 0.6
	var to_animal := (animal.global_position + Vector3(2.5, 0.4, -1.5) - head).normalized()
	assert_float(turned.dot(to_animal)).is_greater(ahead.dot(to_animal) + 0.15)
	assert_float(turned.x).is_greater(ahead.x)  # towards +X


func test_the_head_never_turns_round_behind() -> void:
	_box(Vector3(10, 1, 10), Vector3(0, -0.5, 0))
	var animal := _animal()
	await _frames(30)
	_fauna_at(animal.global_position + Vector3(1.2, 0.0, 3.0))  # behind, a little to the right
	await _frames(60)
	var look := animal.get_node("%HeadLook") as HeadLook
	var head := await _measure_head(look)
	var limit := deg_to_rad(look.settings.yaw_range * 0.5 + 10.0)
	assert_float(head.dot(-animal.global_basis.z)).is_greater(cos(limit))
