## Tests for the Husky species: model structure, fit to the capsule, facing, credits.
extends GdUnitTestSuite

const SPECIES_PATH: String = "res://data/species/husky.tres"
const CAPSULE_LENGTH: float = 1.3  # animal.tscn collision capsule

var _species: AnimalSpecies


func before() -> void:
	_species = load(SPECIES_PATH)


func _placed_model() -> Node3D:
	var model: Node3D = auto_free(_species.model_scene.instantiate())
	model.scale = Vector3.ONE * _species.model_scale
	model.rotation.y = deg_to_rad(_species.model_yaw_degrees)
	add_child(model)
	return model


func _bone_position(model: Node3D, bone: String) -> Vector3:
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	)


func test_species_is_valid_and_reuses_the_tuned_movement() -> void:
	assert_array(Array(_species.get_validation_errors())).is_empty()
	var placeholder := load("res://data/species/placeholder.tres") as AnimalSpecies
	assert_float(_species.run_speed).is_equal(placeholder.run_speed)
	assert_float(_species.jump_height).is_equal(placeholder.jump_height)


func test_model_is_rigged_and_animated() -> void:
	var model := _placed_model()
	assert_int(model.find_children("*", "Skeleton3D", true, false).size()).is_equal(1)
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	for clip: String in ["Idle", "Walk", "Gallop", "Gallop_Jump", "Eating"]:
		assert_bool(player.has_animation(clip)).override_failure_message(clip).is_true()


func test_scaled_model_matches_the_capsule_and_faces_forward() -> void:
	var model := _placed_model()
	await get_tree().process_frame
	var head := _bone_position(model, "Head")
	var tail := _bone_position(model, "Tail6")
	assert_float(head.z).is_less(tail.z)  # forward is -Z
	var length := absf(tail.z - head.z)
	assert_float(length).is_between(CAPSULE_LENGTH * 0.7, CAPSULE_LENGTH * 1.3)
	var paw := _bone_position(model, "FF.L")
	assert_float(paw.y).is_between(-0.05, 0.1)  # paws on the ground


func test_model_is_credited_with_its_licence() -> void:
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	assert_str(credits).contains("assets/animals/husky/husky.glb")
	var licence := FileAccess.get_file_as_string("res://assets/animals/husky/LICENSE.md")
	assert_str(licence).contains("CC0")
	assert_str(licence).contains("Quaternius")
