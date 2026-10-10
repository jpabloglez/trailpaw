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
		&"heron":
			return _heron()
		&"owl":
			return _owl()
		&"chicken":
			var white := Color(0.95, 0.93, 0.88)
			var red := Color(0.85, 0.15, 0.12)
			var yellow := Color(0.95, 0.72, 0.2)
			var dark := Color(0.05, 0.04, 0.03)
			return ellipsoids(
				[
					[Vector3(0, 0.16, 0.01), Vector3(0.08, 0.075, 0.11), white],
					[Vector3(0, 0.2, 0.11), Vector3(0.045, 0.06, 0.04), white],  # the tail
					[Vector3(0, 0.27, -0.08), Vector3(0.045, 0.05, 0.045), white],
					[Vector3(0, 0.325, -0.08), Vector3(0.012, 0.025, 0.03), red],  # the comb
					[Vector3(0, 0.24, -0.125), Vector3(0.01, 0.02, 0.01), red],  # the wattle
					[Vector3(0, 0.265, -0.13), Vector3(0.012, 0.01, 0.022), yellow],  # the beak
					[Vector3(-0.03, 0.285, -0.11), Vector3(0.008, 0.008, 0.008), dark],
					[Vector3(0.03, 0.285, -0.11), Vector3(0.008, 0.008, 0.008), dark],
					[Vector3(-0.03, 0.05, 0.0), Vector3(0.008, 0.05, 0.008), yellow],
					[Vector3(0.03, 0.05, 0.0), Vector3(0.008, 0.05, 0.008), yellow],
				]
			)
		&"squirrel":
			var fur := Color(0.62, 0.33, 0.16)
			var belly := Color(0.86, 0.72, 0.55)
			var dark := Color(0.06, 0.04, 0.03)
			return ellipsoids(
				[
					[Vector3(0, 0.07, 0.0), Vector3(0.045, 0.05, 0.075), fur],
					[Vector3(0, 0.06, -0.02), Vector3(0.035, 0.04, 0.05), belly],
					[Vector3(0, 0.11, -0.07), Vector3(0.035, 0.034, 0.04), fur],
					[Vector3(-0.018, 0.145, -0.07), Vector3(0.008, 0.016, 0.008), fur],
					[Vector3(0.018, 0.145, -0.07), Vector3(0.008, 0.016, 0.008), fur],
					[Vector3(-0.02, 0.12, -0.1), Vector3(0.006, 0.006, 0.006), dark],
					[Vector3(0.02, 0.12, -0.1), Vector3(0.006, 0.006, 0.006), dark],
					[Vector3(0, 0.1, 0.09), Vector3(0.035, 0.05, 0.04), fur],  # the tail, curled up
					[Vector3(0, 0.17, 0.07), Vector3(0.04, 0.05, 0.035), fur],
					[Vector3(0, 0.2, 0.03), Vector3(0.03, 0.03, 0.03), fur],
				]
			)
		&"marmot":  # chubby, brown with a paler belly and a dark short tail
			var fur := Color(0.52, 0.4, 0.27)
			var belly := Color(0.72, 0.6, 0.44)
			var dark := Color(0.2, 0.15, 0.1)
			var eye := Color(0.04, 0.03, 0.03)
			return ellipsoids(
				[
					[Vector3(0, 0.11, 0.02), Vector3(0.1, 0.095, 0.15), fur],
					[Vector3(0, 0.09, -0.02), Vector3(0.08, 0.075, 0.12), belly],
					[Vector3(0, 0.17, -0.14), Vector3(0.065, 0.06, 0.07), fur],
					[Vector3(0, 0.155, -0.2), Vector3(0.035, 0.03, 0.035), belly],  # the muzzle
					[Vector3(-0.045, 0.22, -0.13), Vector3(0.015, 0.015, 0.01), dark],
					[Vector3(0.045, 0.22, -0.13), Vector3(0.015, 0.015, 0.01), dark],
					[Vector3(-0.033, 0.19, -0.19), Vector3(0.009, 0.009, 0.009), eye],
					[Vector3(0.033, 0.19, -0.19), Vector3(0.009, 0.009, 0.009), eye],
					[Vector3(0, 0.12, 0.18), Vector3(0.03, 0.03, 0.06), dark],  # the tail
				]
			)
		&"hedgehog":
			var spines := Color(0.33, 0.27, 0.22)
			var tips := Color(0.62, 0.55, 0.45)
			var face := Color(0.72, 0.62, 0.5)
			var dark := Color(0.05, 0.04, 0.04)
			var parts := [
				[Vector3(0, 0.07, 0.01), Vector3(0.08, 0.065, 0.1), spines],
				[Vector3(0, 0.05, 0.0), Vector3(0.065, 0.045, 0.09), face],
				[Vector3(0, 0.05, -0.1), Vector3(0.035, 0.03, 0.045), face],
				[Vector3(0, 0.045, -0.145), Vector3(0.009, 0.009, 0.009), dark],
				[Vector3(-0.022, 0.065, -0.11), Vector3(0.006, 0.006, 0.006), dark],
				[Vector3(0.022, 0.065, -0.11), Vector3(0.006, 0.006, 0.006), dark],
			]
			for row in 3:  # tufts of spines along the back, pale-tipped
				for side in 3:
					var x := (side - 1) * 0.04
					var z := -0.04 + row * 0.05
					parts.append(
						[Vector3(x, 0.115 - absf(x) * 0.6, z), Vector3(0.018, 0.022, 0.03), tips]
					)
			return ellipsoids(parts, 5, 4)
		&"fish":
			var scales := Color(0.72, 0.76, 0.78)
			return ellipsoids(
				[
					[Vector3(0, 0.0, 0.0), Vector3(0.035, 0.05, 0.15), scales],
					[Vector3(0, 0.025, 0.0), Vector3(0.025, 0.03, 0.13), Color(0.32, 0.4, 0.42)],
					[Vector3(0, 0.0, 0.17), Vector3(0.006, 0.06, 0.05), Color(0.55, 0.6, 0.62)],
					[Vector3(0, 0.055, 0.02), Vector3(0.005, 0.03, 0.04), Color(0.4, 0.46, 0.48)],
					[
						Vector3(-0.025, 0.012, -0.1),
						Vector3(0.006, 0.006, 0.006),
						Color(0.05, 0.05, 0.05)
					],
					[
						Vector3(0.025, 0.012, -0.1),
						Vector3(0.006, 0.006, 0.006),
						Color(0.05, 0.05, 0.05)
					],
				],
				6,
				4
			)
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
		&"frog":
			var skin := Color(0.36, 0.55, 0.24)
			var belly := Color(0.7, 0.72, 0.45)
			var dark := Color(0.06, 0.06, 0.05)
			return ellipsoids(
				[
					[Vector3(0, 0.035, 0.0), Vector3(0.04, 0.028, 0.05), skin],
					[Vector3(0, 0.025, -0.005), Vector3(0.034, 0.018, 0.04), belly],
					[Vector3(0, 0.045, -0.04), Vector3(0.034, 0.024, 0.03), skin],
					[Vector3(-0.021, 0.068, -0.045), Vector3(0.012, 0.012, 0.012), skin],
					[Vector3(0.021, 0.068, -0.045), Vector3(0.012, 0.012, 0.012), skin],
					[Vector3(-0.023, 0.072, -0.052), Vector3(0.006, 0.006, 0.006), dark],
					[Vector3(0.023, 0.072, -0.052), Vector3(0.006, 0.006, 0.006), dark],
					[Vector3(-0.042, 0.02, 0.03), Vector3(0.018, 0.014, 0.04), skin],
					[Vector3(0.042, 0.02, 0.03), Vector3(0.018, 0.014, 0.04), skin],
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


# A tawny owl ≈ 35 cm tall, facing −Z, perching on its origin: a round body, a big head with a
# pale facial disc and dark eyes. Its wings (≈ 0.8 m across) carry their distance from the body
# in UV.x, like the heron's, so shaders/bird.gdshader folds or beats them.
static func _owl() -> ArrayMesh:
	var brown := Color(0.48, 0.34, 0.22)
	var pale := Color(0.82, 0.72, 0.58)
	var dark := Color(0.05, 0.04, 0.03)
	var parts := [
		[Vector3(0, 0.13, 0.0), Vector3(0.09, 0.12, 0.08), brown],
		[Vector3(0, 0.11, -0.03), Vector3(0.07, 0.09, 0.06), pale],
		[Vector3(0, 0.27, -0.01), Vector3(0.085, 0.075, 0.075), brown],
		[Vector3(0, 0.265, -0.05), Vector3(0.065, 0.055, 0.035), pale],
		[Vector3(-0.025, 0.275, -0.08), Vector3(0.014, 0.014, 0.01), dark],
		[Vector3(0.025, 0.275, -0.08), Vector3(0.014, 0.014, 0.01), dark],
		[Vector3(0, 0.25, -0.085), Vector3(0.008, 0.012, 0.01), Color(0.75, 0.62, 0.3)],
		[Vector3(-0.03, 0.01, -0.02), Vector3(0.015, 0.012, 0.025), Color(0.6, 0.55, 0.4)],
		[Vector3(0.03, 0.01, -0.02), Vector3(0.015, 0.012, 0.025), Color(0.6, 0.55, 0.4)],
	]
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 5
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
	tool.set_color(Color(0.42, 0.3, 0.2))
	for side: float in [-1.0, 1.0]:
		for corner: Vector3 in [
			Vector3(0.06 * side, 0.22, -0.05),
			Vector3(0.4 * side, 0.2, 0.06),
			Vector3(0.06 * side, 0.22, 0.09),
		]:
			tool.set_uv(Vector2(absf(corner.x) * side, 0.0))
			tool.add_vertex(corner)
	tool.generate_normals()
	return tool.commit()


# A grey heron ≈ 1 m tall, facing −Z, standing on its origin on long legs, its neck in an S.
# The wings (≈ 1.5 m across) carry their distance from the body in UV.x like the bird's, so
# shaders/bird.gdshader folds them along the body or beats them in flight.
static func _heron() -> ArrayMesh:
	var grey := Color(0.56, 0.59, 0.63)
	var pale := Color(0.86, 0.87, 0.86)
	var dark := Color(0.15, 0.15, 0.17)
	var parts := [
		[Vector3(0, 0.64, 0.02), Vector3(0.09, 0.1, 0.2), grey],
		[Vector3(0, 0.6, 0.0), Vector3(0.075, 0.08, 0.16), pale],
		[Vector3(0, 0.62, 0.23), Vector3(0.06, 0.03, 0.07), grey],
		[Vector3(0, 0.78, -0.13), Vector3(0.035, 0.09, 0.035), pale],
		[Vector3(0, 0.9, -0.16), Vector3(0.03, 0.07, 0.03), pale],
		[Vector3(0, 0.97, -0.19), Vector3(0.04, 0.035, 0.05), pale],
		[Vector3(0, 0.99, -0.16), Vector3(0.014, 0.012, 0.055), dark],
		[Vector3(0, 0.965, -0.28), Vector3(0.011, 0.011, 0.07), Color(0.86, 0.7, 0.3)],
		[Vector3(-0.035, 0.27, 0.03), Vector3(0.012, 0.27, 0.012), Color(0.45, 0.4, 0.3)],
		[Vector3(0.035, 0.27, 0.03), Vector3(0.012, 0.27, 0.012), Color(0.45, 0.4, 0.3)],
	]
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 5
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
	tool.set_color(Color(0.5, 0.53, 0.58))
	for side: float in [-1.0, 1.0]:
		for corner: Vector3 in [
			Vector3(0.07 * side, 0.7, -0.1),
			Vector3(0.75 * side, 0.7, 0.14),
			Vector3(0.07 * side, 0.7, 0.18),
		]:
			tool.set_uv(Vector2(absf(corner.x) * side, 0.0))
			tool.add_vertex(corner)
	tool.generate_normals()
	return tool.commit()


## Hamlet food and its places (Phase 16): [code]&"cabbage"[/code] (≈ 35 cm),
## [code]&"egg"[/code] (≈ 6 cm), [code]&"nest"[/code] (a ring of straw ≈ 50 cm) and
## [code]&"soil"[/code] (a dug bed ≈ 4 × 2.6 m), standing on their origin.
static func hamlet_food(shape: StringName) -> ArrayMesh:
	match shape:
		&"cabbage":
			var outer := Color(0.35, 0.55, 0.25)
			var inner := Color(0.62, 0.78, 0.42)
			return ellipsoids(
				[
					[Vector3(0, 0.1, 0), Vector3(0.17, 0.1, 0.17), outer],
					[Vector3(0.05, 0.13, 0.04), Vector3(0.12, 0.08, 0.12), outer],
					[Vector3(0, 0.15, 0), Vector3(0.1, 0.09, 0.1), inner],
				]
			)
		&"egg":
			return ellipsoids(
				[[Vector3(0, 0.03, 0), Vector3(0.022, 0.03, 0.022), Color(0.97, 0.94, 0.86)]], 6, 4
			)
		&"nest":
			var straw := Color(0.78, 0.66, 0.38)
			var parts := []
			for n in 8:
				var a := n * TAU / 8.0
				parts.append(
					[Vector3(cos(a) * 0.17, 0.04, sin(a) * 0.17), Vector3(0.1, 0.045, 0.1), straw]
				)
			parts.append([Vector3(0, 0.015, 0), Vector3(0.18, 0.015, 0.18), straw.darkened(0.15)])
			return ellipsoids(parts, 6, 3)
	return ellipsoids(
		[[Vector3(0, 0.0, 0), Vector3(2.0, 0.04, 1.3), Color(0.36, 0.25, 0.16)]], 8, 3
	)


## A firefly ≈ 2 cm long, facing −Z, centred on its origin: a dark body with a pale abdomen and
## two folded wing covers (the glow is added by whoever shows it).
static func firefly() -> ArrayMesh:
	var body := Color(0.18, 0.16, 0.14)
	return ellipsoids(
		[
			[Vector3(0, 0.003, -0.0085), Vector3(0.003, 0.0028, 0.0035), Color(0.75, 0.35, 0.2)],
			[Vector3(0, 0.003, 0.0), Vector3(0.005, 0.004, 0.008), body],
			[Vector3(0, 0.002, 0.009), Vector3(0.0045, 0.0035, 0.005), Color(0.85, 0.85, 0.55)],
			[Vector3(-0.003, 0.005, 0.002), Vector3(0.003, 0.002, 0.01), body],
			[Vector3(0.003, 0.005, 0.002), Vector3(0.003, 0.002, 0.01), body],
		],
		5,
		3
	)


## A dragonfly ≈ 7 cm long and 9 cm across, facing −Z, centred on its origin: a long slim body
## (tinted by the instance colour) and two pairs of narrow, pale wings whose vertices carry their
## distance from the body in [code]UV.x[/code], so [code]shaders/bird.gdshader[/code] beats them.
static func dragonfly() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 5
	sphere.rings = 3
	var source := sphere.get_mesh_arrays()
	var unit_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	tool.set_uv(Vector2.ZERO)
	tool.set_color(Color.WHITE)
	for part: Array in [
		[Vector3(0, 0, -0.022), Vector3(0.006, 0.006, 0.008)],  # head
		[Vector3(0, 0, -0.01), Vector3(0.005, 0.005, 0.012)],  # thorax
		[Vector3(0, 0, 0.018), Vector3(0.0025, 0.0025, 0.03)],  # abdomen
	]:
		for index: int in source[Mesh.ARRAY_INDEX]:
			tool.add_vertex(
				(part[0] as Vector3) + unit_vertices[index] * 2.0 * (part[1] as Vector3)
			)
	tool.set_color(Color(0.86, 0.92, 0.96))
	for side: float in [-1.0, 1.0]:
		for wing: Array in [
			[Vector3(0.003, 0, -0.014), Vector3(0.046, 0, -0.016), Vector3(0.044, 0, -0.006)],
			[Vector3(0.003, 0, -0.006), Vector3(0.042, 0, -0.002), Vector3(0.04, 0, 0.007)],
		]:
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
