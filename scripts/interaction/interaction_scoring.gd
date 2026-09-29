class_name InteractionScoring
extends RefCounted
## Pure target scoring for the [Interactor]: closer and more in front scores higher.


## Score of a target at [param target] for an animal at [param origin] facing
## [param forward] (horizontal unit vector). Returns a value in (0, 1], or -1 when the target
## is beyond [param max_distance] or more than [param max_angle_degrees] off the facing
## direction. [param distance_weight] (0…1) trades distance against facing.
static func score(
	origin: Vector3,
	forward: Vector3,
	target: Vector3,
	max_distance: float,
	max_angle_degrees: float,
	distance_weight: float
) -> float:
	var offset := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var distance := offset.length()
	if distance > max_distance:
		return -1.0
	var facing := 1.0
	if distance > 1e-4:
		var angle := rad_to_deg(forward.angle_to(offset / distance))
		if angle > max_angle_degrees:
			return -1.0
		facing = 1.0 - angle / 180.0
	var closeness := 1.0 - distance / max_distance
	return maxf(1e-4, lerpf(facing, closeness, distance_weight))
