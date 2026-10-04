class_name LegIK
extends SkeletonModifier3D
## Two-bone IK for the legs: for each leg (upper bone → lower bone → paw tip) it moves the paw
## tip [member offsets] metres straight up or down from where the animation put it, bending the
## knee. With an offset of 0 the leg is left exactly as animated. [FootPlanter] sets the offsets
## from the ground under each paw and fades [member SkeletonModifier3D.influence].
##
## Analytical solution in skeleton space (law of cosines for the knee, then a swing of the
## upper bone towards the target), keeping the animated bend plane.
## [br][br]
## Budget: a few vector ops and two bone rotations per leg per skeleton update; no allocations.

## Animated paw tip of each leg (world), written every update before the IK (read by
## [FootPlanter] to probe the ground there).
var tips := PackedVector3Array()
## Vertical move of each leg's paw tip (m, world up), set by [FootPlanter].
var offsets := PackedFloat32Array()

var _upper := PackedInt32Array()
var _lower := PackedInt32Array()
var _tip_local := PackedVector3Array()


## Configures the legs from [param chains] ("upper>lower>paw" bone names; the paw bone gives the
## tip's place along the lower bone in the rest pose). Returns how many legs were found.
func setup(skeleton: Skeleton3D, chains: PackedStringArray) -> int:
	_upper.clear()
	_lower.clear()
	_tip_local.clear()
	for chain in chains:
		var names := chain.split(">")
		if names.size() != 3:
			continue
		var upper := skeleton.find_bone(names[0])
		var lower := skeleton.find_bone(names[1])
		var paw := skeleton.find_bone(names[2])
		if upper < 0 or lower < 0 or paw < 0:
			continue
		var lower_rest := skeleton.get_bone_global_rest(lower)
		var paw_rest := skeleton.get_bone_global_rest(paw)
		_upper.append(upper)
		_lower.append(lower)
		_tip_local.append(lower_rest.affine_inverse() * paw_rest.origin)
	tips.resize(_upper.size())
	offsets.resize(_upper.size())
	offsets.fill(0.0)
	return _upper.size()


## Number of legs configured.
func leg_count() -> int:
	return _upper.size()


## Paw tip of leg [param i] (world). After the IK only when called from
## [signal Skeleton3D.skeleton_updated]: elsewhere the skeleton reports the animated pose (modifier
## results are not kept between updates).
func tip_now(i: int) -> Vector3:
	var skeleton := get_skeleton()
	return skeleton.global_transform * (skeleton.get_bone_global_pose(_lower[i]) * _tip_local[i])


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for i in _upper.size():
		var tip := (
			skeleton.global_transform * (skeleton.get_bone_global_pose(_lower[i]) * _tip_local[i])
		)
		tips[i] = tip
		if absf(offsets[i]) < 0.001:
			continue
		_solve(skeleton, i, to_skeleton * (tip + Vector3.UP * offsets[i]))


func _solve(skeleton: Skeleton3D, i: int, target: Vector3) -> void:
	var a_pose := skeleton.get_bone_global_pose(_upper[i])
	var b_pose := skeleton.get_bone_global_pose(_lower[i])
	var a := a_pose.origin
	var b := b_pose.origin
	var c := b_pose * _tip_local[i]
	var lab := a.distance_to(b)
	var lcb := b.distance_to(c)
	if lab < 1e-6 or lcb < 1e-6:
		return
	var lat := clampf(a.distance_to(target), 1e-6, (lab + lcb) * 0.999)
	var ac_ab_0 := _angle(c - a, b - a)
	var ba_bc_0 := _angle(a - b, c - b)
	var ac_at_0 := _angle(c - a, target - a)
	var ac_ab_1 := acos(clampf((lcb * lcb - lab * lab - lat * lat) / (-2.0 * lab * lat), -1.0, 1.0))
	var ba_bc_1 := acos(clampf((lat * lat - lab * lab - lcb * lcb) / (-2.0 * lab * lcb), -1.0, 1.0))
	var bend := (c - a).cross(b - a)
	if bend.length_squared() < 1e-12:
		bend = a_pose.basis.x  # straight leg: bend around the hip's hinge
	bend = bend.normalized()
	var a_rotation := a_pose.basis.get_rotation_quaternion()
	var b_rotation := b_pose.basis.get_rotation_quaternion()
	var a_local := skeleton.get_bone_pose_rotation(_upper[i])
	var b_local := skeleton.get_bone_pose_rotation(_lower[i])
	a_local = a_local * Quaternion((a_rotation.inverse() * bend).normalized(), ac_ab_1 - ac_ab_0)
	b_local = b_local * Quaternion((b_rotation.inverse() * bend).normalized(), ba_bc_1 - ba_bc_0)
	var swing := (c - a).cross(target - a)
	if swing.length_squared() > 1e-12:
		var axis := (a_rotation.inverse() * swing.normalized()).normalized()
		a_local = a_local * Quaternion(axis, ac_at_0)
	skeleton.set_bone_pose_rotation(_upper[i], a_local)
	skeleton.set_bone_pose_rotation(_lower[i], b_local)


static func _angle(u: Vector3, v: Vector3) -> float:
	return acos(clampf(u.normalized().dot(v.normalized()), -1.0, 1.0))
