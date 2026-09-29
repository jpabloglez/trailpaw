class_name NeedIcon
extends RefCounted
## Simple silhouettes for the needs HUD, drawn in code (no image assets): a drop (thirst), an
## apple (hunger), a sun (temperature comfort) and a moon (energy).
##
## Shapes are built from polygons and circles in a unit box centred on the origin and drawn
## with [method draw] on any [CanvasItem].

## Known shapes (see [member NeedDefinition.icon_shape]).
const SHAPES: Array[String] = ["drop", "apple", "sun", "moon"]
## Vertices per curved outline.
const SEGMENTS: int = 32


## Draws [param shape] centred at [param center] with half-size [param radius].
static func draw(
	canvas: CanvasItem, shape: String, center: Vector2, radius: float, color: Color
) -> void:
	match shape:
		"drop":
			canvas.draw_colored_polygon(_offset(drop_points(radius), center), color)
		"apple":
			for c: Vector2 in [Vector2(-0.24, 0.12), Vector2(0.24, 0.12), Vector2(0.0, 0.3)]:
				canvas.draw_circle(center + c * radius, radius * 0.5, color)
			var stem_top := center + Vector2(0.12, -0.78) * radius
			canvas.draw_line(center + Vector2(0.0, -0.3) * radius, stem_top, color, radius * 0.14)
			canvas.draw_colored_polygon(_offset(leaf_points(radius), center), color)
		"sun":
			canvas.draw_circle(center, radius * 0.42, color)
			for i in 8:
				var dir := Vector2.from_angle(TAU * i / 8.0)
				canvas.draw_line(
					center + dir * radius * 0.6, center + dir * radius * 0.92, color, radius * 0.14
				)
		"moon":
			canvas.draw_colored_polygon(_offset(moon_points(radius), center), color)


## Teardrop outline, tip up: x = sin t · sin(t/2), y = −cos t.
static func drop_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in SEGMENTS:
		var t := TAU * i / SEGMENTS
		points.append(Vector2(0.8 * sin(t) * sin(t * 0.5), -0.92 * cos(t)) * radius)
	return points


## Small leaf next to the apple stem.
static func leaf_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var rotation := deg_to_rad(-30.0)
	for i in SEGMENTS / 2:
		var t := TAU * i / (SEGMENTS / 2)
		var p := Vector2(cos(t) * 0.26, sin(t) * 0.11).rotated(rotation)
		points.append((p + Vector2(0.36, -0.66)) * radius)
	return points


## Crescent: the outer disc minus a disc offset up and to the right.
static func moon_points(radius: float) -> PackedVector2Array:
	var outer := 0.82
	var inner := 0.7
	var offset := Vector2(0.38, -0.26)
	var distance := offset.length()
	var towards := offset.angle()
	# Half-angles of the two intersection points, seen from each circle's centre.
	var alpha := acos(
		(outer * outer + distance * distance - inner * inner) / (2.0 * outer * distance)
	)
	var beta := acos(
		(inner * inner + distance * distance - outer * outer) / (2.0 * inner * distance)
	)
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var a := towards + alpha + (TAU - 2.0 * alpha) * i / SEGMENTS
		points.append(Vector2.from_angle(a) * outer * radius)
	var away := towards + PI
	for i in range(1, SEGMENTS):
		var a := away + beta - 2.0 * beta * i / SEGMENTS
		points.append((offset + Vector2.from_angle(a) * inner) * radius)
	return points


static func _offset(points: PackedVector2Array, center: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for p in points:
		moved.append(p + center)
	return moved
