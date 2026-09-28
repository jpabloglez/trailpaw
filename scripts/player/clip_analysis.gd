class_name ClipAnalysis
extends RefCounted
## Measures properties of skeletal animation clips by sampling paw bones: the ground speed a
## locomotion clip is authored for (a planted paw slides backwards relative to the body at that
## speed) and the instants each paw touches down. Used to author species data and footsteps.
##
## [param model] must be inside the tree with its final scale (bone positions are global).

## Samples per clip cycle.
const SAMPLES: int = 120
## Height above a paw's lowest point that still counts as planted (m).
const CONTACT_TOLERANCE: float = 0.02


## Authored ground speed (m/s) of [param clip], averaged over [param paws].
static func ground_speed(model: Node3D, clip: String, paws: PackedStringArray) -> float:
	var total := 0.0
	for paw in paws:
		var track := _sample(model, clip, paw)
		var ys: PackedFloat32Array = track[0]
		var zs: PackedFloat32Array = track[1]
		var step: float = track[2]
		var floor_y := _min(ys)
		var dz := 0.0
		var dt := 0.0
		for i in SAMPLES:
			var j := (i + 1) % SAMPLES
			if ys[i] < floor_y + CONTACT_TOLERANCE and ys[j] < floor_y + CONTACT_TOLERANCE:
				dz += zs[j] - zs[i]
				dt += step
		total += absf(dz / maxf(dt, 1e-6))
	return total / paws.size()


## Clip times (s) at which [param paw] touches down (enters its planted phase).
static func contact_times(model: Node3D, clip: String, paw: String) -> PackedFloat32Array:
	var track := _sample(model, clip, paw)
	var ys: PackedFloat32Array = track[0]
	var step: float = track[2]
	var floor_y := _min(ys)
	var times := PackedFloat32Array()
	for i in SAMPLES:
		var previous := ys[(i - 1 + SAMPLES) % SAMPLES]
		if ys[i] < floor_y + CONTACT_TOLERANCE and previous >= floor_y + CONTACT_TOLERANCE:
			times.append(i * step)
	return times


## [ys, zs, step]: paw height and forward position over one cycle of [param clip].
static func _sample(model: Node3D, clip: String, paw: String) -> Array:
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var bone := skeleton.find_bone(paw)
	var length := player.get_animation(clip).length
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for i in SAMPLES:
		player.play(clip)
		player.seek(length * i / SAMPLES, true)
		var p := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		ys.append(p.y)
		zs.append(p.z)
	player.stop()
	return [ys, zs, length / SAMPLES]


static func _min(values: PackedFloat32Array) -> float:
	var lowest := INF
	for v in values:
		lowest = minf(lowest, v)
	return lowest
