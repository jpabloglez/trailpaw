class_name FaunaSteering
extends RefCounted
## Pure steering helpers: pick a walkable direction close to the desired one, and push away
## from neighbours.

## Angles tried after the desired direction, alternating sides (degrees).
const TRY_ANGLES: Array[float] = [30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 135.0, -135.0]


## First direction, starting at [param desired] (horizontal unit vector) and turning further
## away on alternating sides, for which [param is_clear] ([code]func(dir: Vector3) -> bool[/code])
## holds; zero when everything is blocked.
static func clear_direction(desired: Vector3, is_clear: Callable) -> Vector3:
	if desired.length_squared() < 1e-6:
		return Vector3.ZERO
	if is_clear.call(desired):
		return desired
	for angle in TRY_ANGLES:
		var dir := desired.rotated(Vector3.UP, deg_to_rad(angle))
		if is_clear.call(dir):
			return dir
	return Vector3.ZERO


## Horizontal push away from [param neighbours] closer than [param radius] to [param origin],
## stronger when closer (length ≤ 1).
static func separation(origin: Vector3, neighbours: PackedVector3Array, radius: float) -> Vector3:
	var push := Vector3.ZERO
	for other in neighbours:
		var away := Vector3(origin.x - other.x, 0.0, origin.z - other.z)
		var distance := away.length()
		if distance < 1e-4 or distance >= radius:
			continue
		push += away / distance * (1.0 - distance / radius)
	return push.limit_length(1.0)
