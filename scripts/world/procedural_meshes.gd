class_name ProceduralMeshes
extends RefCounted
## Low-poly meshes built in code where the CC0 packs have nothing suitable: a round berry bush,
## berry clusters and fallen fruit. Each is made of spheres, stands on its origin and is about
## 1 m across (scaled per instance).

## Known shapes (see [member VegetationType.procedural_shape]).
const SHAPES: Array[StringName] = [
	&"bush", &"berry_cluster", &"fruit", &"reeds", &"cattails", &"water_lily", &"water_lily_flower"
]
## Shapes whose colours are in the vertex colours (the foliage material multiplies them in).
const COLOURED: Array[StringName] = [&"cattails", &"water_lily", &"water_lily_flower"]


## Mesh for [param shape] (no material).
static func build(shape: StringName) -> ArrayMesh:
	match shape:
		&"reeds":
			return _tuft(9, Vector2(0.8, 1.3), 0.035, 0.22, Color.WHITE, false)
		&"cattails":
			return _tuft(6, Vector2(0.9, 1.4), 0.03, 0.16, Color(0.42, 0.55, 0.3), true)
		&"water_lily":
			return _lily_pad(false)
		&"water_lily_flower":
			return _lily_pad(true)
		&"bush":
			return spheres(
				[
					Vector4(0.0, 0.38, 0.0, 0.44),
					Vector4(0.24, 0.26, 0.1, 0.3),
					Vector4(-0.22, 0.25, 0.15, 0.3),
					Vector4(0.03, 0.25, -0.24, 0.3),
				],
				Vector3(1.0, 0.85, 1.0),
				7,
				5
			)
		&"berry_cluster":
			return spheres(
				[
					Vector4(0.0, 0.3, 0.0, 0.3),
					Vector4(0.28, 0.24, 0.12, 0.24),
					Vector4(-0.24, 0.26, 0.18, 0.25),
					Vector4(0.05, 0.25, -0.28, 0.24),
					Vector4(-0.1, 0.62, 0.02, 0.22),
				],
				Vector3.ONE,
				6,
				4
			)
	return spheres([Vector4(0.0, 0.46, 0.0, 0.5)], Vector3(1.0, 0.9, 1.0), 8, 4)


## One surface made of spheres (centre xyz, radius w), each scaled by [param squash], with flat
## faces (low-poly look).
static func spheres(
	parts: Array[Vector4], squash: Vector3, radial_segments: int, rings: int
) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = radial_segments
	sphere.rings = rings
	var source := sphere.get_mesh_arrays()
	var unit_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var unit_indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var centre := Vector3(part.x, part.y, part.z)
		for index in unit_indices:
			# SphereMesh vertices have radius 0.5.
			tool.add_vertex(centre + unit_vertices[index] * 2.0 * part.w * squash)
	tool.generate_normals()  # unindexed: flat shading
	return tool.commit()


## One vertex-coloured surface of ellipsoids, flat shaded (low-poly critters). Each part is
## [code][centre: Vector3, radii: Vector3, colour: Color][/code].
static func ellipsoids(parts: Array, radial_segments: int = 7, rings: int = 5) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = radial_segments
	sphere.rings = rings
	var source := sphere.get_mesh_arrays()
	var unit_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var unit_indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var centre: Vector3 = part[0]
		var radii: Vector3 = part[1]
		tool.set_color(part[2])
		for index in unit_indices:
			tool.add_vertex(centre + unit_vertices[index] * 2.0 * radii)  # unit radius 0.5
	tool.generate_normals()
	return tool.commit()


## A small animal facing −Z, standing on its origin (≈ its real size in metres).
static func critter(shape: StringName) -> ArrayMesh:
	match shape:
		&"rabbit":
			var fur := Color(0.56, 0.47, 0.38)
			var dark := Color(0.42, 0.34, 0.27)
			return ellipsoids(
				[
					[Vector3(0, 0.12, 0.03), Vector3(0.09, 0.085, 0.13), fur],
					[Vector3(0, 0.1, 0.1), Vector3(0.1, 0.09, 0.08), fur],
					[Vector3(0, 0.2, -0.1), Vector3(0.062, 0.062, 0.075), fur],
					[Vector3(-0.03, 0.3, -0.08), Vector3(0.017, 0.075, 0.03), dark],
					[Vector3(0.03, 0.3, -0.08), Vector3(0.017, 0.075, 0.03), dark],
					[Vector3(0, 0.15, 0.18), Vector3(0.035, 0.035, 0.035), Color(0.95, 0.94, 0.9)],
					[
						Vector3(-0.042, 0.22, -0.15),
						Vector3(0.011, 0.011, 0.011),
						Color(0.08, 0.06, 0.05)
					],
					[
						Vector3(0.042, 0.22, -0.15),
						Vector3(0.011, 0.011, 0.011),
						Color(0.08, 0.06, 0.05)
					],
				]
			)
		&"duck":
			var eye := Color(0.05, 0.05, 0.05)
			return ellipsoids(
				[
					[Vector3(0, 0.05, 0.02), Vector3(0.085, 0.055, 0.14), Color(0.56, 0.5, 0.42)],
					[Vector3(0, 0.08, 0.15), Vector3(0.04, 0.03, 0.05), Color(0.3, 0.27, 0.24)],
					[Vector3(0, 0.11, -0.08), Vector3(0.036, 0.02, 0.036), Color(0.95, 0.95, 0.92)],
					[Vector3(0, 0.15, -0.1), Vector3(0.045, 0.045, 0.05), Color(0.12, 0.38, 0.22)],
					[Vector3(0, 0.145, -0.155), Vector3(0.022, 0.01, 0.03), Color(0.92, 0.7, 0.2)],
					[Vector3(-0.034, 0.165, -0.12), Vector3(0.009, 0.009, 0.009), eye],
					[Vector3(0.034, 0.165, -0.12), Vector3(0.009, 0.009, 0.009), eye],
				]
			)
	return ellipsoids([[Vector3(0, 0.1, 0), Vector3(0.1, 0.1, 0.1), Color.WHITE]])


## A small songbird facing −Z, ≈ 20 cm long and 30 cm across the wings, standing on its origin.
## The two wings are flat triangles whose vertices carry their distance from the body in
## [code]UV.x[/code] (negative on the left, 0 on the body), so a shader can flap them
## ([code]shaders/bird.gdshader[/code]).
static func bird() -> ArrayMesh:
	var plumage := Color(1, 1, 1)  # tinted per flock (instance colour)
	var belly := Color(0.92, 0.88, 0.8)
	var parts := [
		[Vector3(0, 0.07, 0.0), Vector3(0.035, 0.035, 0.07), plumage],
		[Vector3(0, 0.06, -0.01), Vector3(0.03, 0.028, 0.05), belly],
		[Vector3(0, 0.1, -0.06), Vector3(0.026, 0.026, 0.028), plumage],
		[Vector3(0, 0.098, -0.092), Vector3(0.007, 0.007, 0.014), Color(0.85, 0.65, 0.2)],
		[Vector3(0, 0.08, 0.085), Vector3(0.02, 0.006, 0.04), plumage],
	]
	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 4
	var source := sphere.get_mesh_arrays()
	var unit_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var unit_indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_uv(Vector2.ZERO)
	for part: Array in parts:
		tool.set_color(part[2])
		for index in unit_indices:
			tool.add_vertex(
				(part[0] as Vector3) + unit_vertices[index] * 2.0 * (part[1] as Vector3)
			)
	tool.set_color(plumage)
	for side: float in [-1.0, 1.0]:
		var root_front := Vector3(0.025 * side, 0.08, -0.025)
		var root_back := Vector3(0.025 * side, 0.08, 0.035)
		var tip := Vector3(0.16 * side, 0.08, 0.03)
		for corner in [root_front, tip, root_back]:
			tool.set_uv(Vector2(absf(corner.x) * side, 0.0))
			tool.add_vertex(corner)
	tool.generate_normals()
	return tool.commit()


## A butterfly ≈ 9 cm across, facing −Z, centred on its origin: a slim body and two pairs of
## wings whose vertices carry their distance from the body in [code]UV.x[/code] like the bird's,
## so the same shader flaps them (faster). Tinted by the instance colour.
static func butterfly() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 5
	sphere.rings = 3
	var source := sphere.get_mesh_arrays()
	var unit_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	tool.set_uv(Vector2.ZERO)
	tool.set_color(Color(0.25, 0.22, 0.2))
	for index: int in source[Mesh.ARRAY_INDEX]:
		tool.add_vertex(unit_vertices[index] * 2.0 * Vector3(0.005, 0.005, 0.028))
	tool.set_color(Color.WHITE)
	for side: float in [-1.0, 1.0]:
		var wings := [
			[Vector3(0.004, 0, -0.018), Vector3(0.05, 0, -0.03), Vector3(0.042, 0, 0.004)],
			[Vector3(0.004, 0, -0.002), Vector3(0.036, 0, 0.012), Vector3(0.006, 0, 0.026)],
		]
		for wing: Array in wings:
			for corner: Vector3 in wing:
				var point := Vector3(corner.x * side, corner.y, corner.z)
				tool.set_uv(Vector2(absf(point.x) * side, 0.0))
				tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()


# A tuft of [param count] slender blades (thin vertical triangles leaning outwards), heights
# in [param heights] (m); with [param heads], a few stems carry a brown cattail head.
# Deterministic: angles and lengths come from the blade index.
static func _tuft(
	count: int, heights: Vector2, width: float, lean: float, colour: Color, heads: bool
) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_color(colour)
	for i in count:
		var angle := float(i) * 2.399963  # golden angle: an even spread
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x) * width
		var height := lerpf(heights.x, heights.y, fmod(float(i) * 0.618034, 1.0))
		var base := out * 0.03
		var tip := out * lean * height + Vector3.UP * height
		tool.add_vertex(base - side)
		tool.add_vertex(base + side)
		tool.add_vertex(tip)
	if heads:
		var head := Color(0.4, 0.27, 0.16)
		for i in 3:
			var angle := float(i) * 2.1 + 0.4
			var out := Vector3(cos(angle), 0.0, sin(angle)) * 0.05
			var top := heights.y * (0.92 - 0.08 * i)
			tool.set_color(colour)
			tool.add_vertex(out + Vector3(-0.008, 0.0, 0.0))
			tool.add_vertex(out + Vector3(0.008, 0.0, 0.0))
			tool.add_vertex(out + Vector3(0.0, top, 0.0))
			tool.set_color(head)
			var sphere := SphereMesh.new()
			sphere.radial_segments = 5
			sphere.rings = 3
			var source := sphere.get_mesh_arrays()
			var unit: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
			for index: int in source[Mesh.ARRAY_INDEX]:
				tool.add_vertex(
					(
						out
						+ Vector3(0.0, top - 0.12, 0.0)
						+ unit[index] * 2.0 * Vector3(0.02, 0.07, 0.02)
					)
				)
	tool.generate_normals()
	return tool.commit()


# A floating lily pad (a flat disc with a notch, ≈ 0.5 m), optionally with a flower.
static func _lily_pad(flower: bool) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_color(Color(0.28, 0.5, 0.24))
	var steps := 14
	var notch := 0.5  # radians left open
	for i in steps:
		var a0 := notch * 0.5 + (TAU - notch) * float(i) / steps
		var a1 := notch * 0.5 + (TAU - notch) * float(i + 1) / steps
		tool.add_vertex(Vector3(0.0, 0.012, 0.0))
		tool.add_vertex(Vector3(cos(a1), 0.0, sin(a1)) * 0.25 + Vector3.UP * 0.012)
		tool.add_vertex(Vector3(cos(a0), 0.0, sin(a0)) * 0.25 + Vector3.UP * 0.012)
	if flower:
		var petal := Color(0.98, 0.88, 0.92)
		for i in 6:
			var angle := float(i) * TAU / 6.0
			var out := Vector3(cos(angle), 0.0, sin(angle))
			var side := Vector3(-out.z, 0.0, out.x) * 0.025
			tool.set_color(petal)
			tool.add_vertex(Vector3(0.0, 0.03, 0.0) - side)
			tool.add_vertex(Vector3(0.0, 0.03, 0.0) + side)
			tool.add_vertex(out * 0.07 + Vector3.UP * 0.07)
		tool.set_color(Color(0.98, 0.82, 0.3))
		tool.add_vertex(Vector3(-0.015, 0.05, 0.0))
		tool.add_vertex(Vector3(0.015, 0.05, 0.0))
		tool.add_vertex(Vector3(0.0, 0.065, 0.015))
	tool.generate_normals()
	return tool.commit()
