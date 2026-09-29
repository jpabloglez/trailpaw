class_name ProceduralMeshes
extends RefCounted
## Low-poly meshes built in code where the CC0 packs have nothing suitable: a round berry bush,
## berry clusters and fallen fruit. Each is made of spheres, stands on its origin and is about
## 1 m across (scaled per instance).

## Known shapes (see [member VegetationType.procedural_shape]).
const SHAPES: Array[StringName] = [&"bush", &"berry_cluster", &"fruit"]


## Mesh for [param shape] (no material).
static func build(shape: StringName) -> ArrayMesh:
	match shape:
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
