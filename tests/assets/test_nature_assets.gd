## Tests for the imported Kenney Nature Kit selection: loadable, MultiMesh-friendly, credited.
extends GdUnitTestSuite

const DIR: String = "res://assets/environment/nature"
const CREDITS: String = "res://assets/CREDITS.md"


func _models() -> PackedStringArray:
	var models := PackedStringArray()
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".glb"):
			models.append(file)
	return models


func test_selection_is_curated_not_the_whole_pack() -> void:
	assert_int(_models().size()).is_between(15, 40)


func test_every_model_is_a_single_mesh_standing_on_its_origin() -> void:
	for file in _models():
		var root: Node = load(DIR.path_join(file)).instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).override_failure_message("%s: one mesh expected" % file).is_equal(
			1
		)
		var aabb := (meshes[0] as MeshInstance3D).get_aabb()
		# MultiMesh instances are placed by their origin: the base must sit at y = 0.
		assert_float(aabb.position.y).override_failure_message("%s base" % file).is_equal_approx(
			0.0, 0.01
		)
		root.free()


func test_every_model_is_credited_and_licence_is_kept() -> void:
	var credits := FileAccess.get_file_as_string(CREDITS)
	for file in _models():
		assert_str(credits).contains(DIR.trim_prefix("res://").path_join(file))
	assert_bool(FileAccess.file_exists(DIR.path_join("License.txt"))).is_true()
	assert_str(FileAccess.get_file_as_string(DIR.path_join("License.txt"))).contains("CC0")
