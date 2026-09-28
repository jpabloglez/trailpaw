class_name WindSettings
extends Resource
## Wind for foliage sway, published to shaders as the [code]wind[/code] global uniform (so
## weather can change it later). Values live in [code]data/world/wind.tres[/code].

## Direction the wind blows towards, in degrees on the XZ plane (0 = +X).
@export_range(0.0, 360.0, 1.0, "suffix:°") var direction_degrees: float = 0.0
## Sway amplitude at the top of a plant with sway 1.
@export_range(0.0, 2.0, 0.01, "suffix:m") var strength: float = 0.0
## Gust frequency.
@export_range(0.0, 10.0, 0.05, "suffix:rad/s") var speed: float = 0.0


## Packed value for the [code]wind[/code] global shader uniform.
func as_uniform() -> Vector4:
	var d := Vector2.from_angle(deg_to_rad(direction_degrees))
	return Vector4(d.x, d.y, strength, speed)
