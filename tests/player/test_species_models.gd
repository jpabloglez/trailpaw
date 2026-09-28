## Tests for every species with a model: structure, fit to the capsule, facing, credits.
extends GdUnitTestSuite

const SPECIES_PATHS: Array[String] = [
	"res://data/species/husky.tres",
	"res://data/species/fox.tres",
]
const CAPSULE_LENGTH: float = 1.3  # animal.tscn collision capsule


func _placed_model(species: AnimalSpecies) -> Node3D:
	var model: Node3D = auto_free(species.model_scene.instantiate())
	model.scale = Vector3.ONE * species.model_scale
	model.rotation.y = deg_to_rad(species.model_yaw_degrees)
	add_child(model)
	return model


func _bone_position(model: Node3D, bone: String) -> Vector3:
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	)


func test_species_are_valid_and_reuse_the_tuned_movement() -> void:
	var placeholder := load("res://data/species/placeholder.tres") as AnimalSpecies
	for path in SPECIES_PATHS:
		var species := load(path) as AnimalSpecies
		assert_array(Array(species.get_validation_errors())).is_empty()
		assert_float(species.run_speed).is_equal(placeholder.run_speed)
		assert_float(species.jump_height).is_equal(placeholder.jump_height)


func test_models_are_rigged_and_animated() -> void:
	for path in SPECIES_PATHS:
		var model := _placed_model(load(path))
		assert_int(model.find_children("*", "Skeleton3D", true, false).size()).is_equal(1)
		var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
		for clip: String in ["Idle", "Walk", "Gallop", "Gallop_Jump", "Eating"]:
			(
				assert_bool(player.has_animation(clip))
				. override_failure_message(path + " " + clip)
				. is_true()
			)


func test_scaled_models_match_the_capsule_and_face_forward() -> void:
	for path in SPECIES_PATHS:
		var model := _placed_model(load(path))
		await get_tree().process_frame
		var head := _bone_position(model, "Head")
		var tail := _bone_position(model, _tail_tip(model))
		assert_float(head.z).override_failure_message(path).is_less(tail.z)  # forward is -Z
		var length := absf(tail.z - head.z)
		assert_float(length).override_failure_message(path).is_between(
			CAPSULE_LENGTH * 0.7, CAPSULE_LENGTH * 1.3
		)
		var paw := _bone_position(model, "FF.L")
		assert_float(paw.y).is_between(-0.05, 0.1)  # paws on the ground


func test_models_are_credited_with_their_licence() -> void:
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for animal: String in ["husky", "fox"]:
		assert_str(credits).contains("assets/animals/%s/%s.glb" % [animal, animal])
		var licence := FileAccess.get_file_as_string("res://assets/animals/%s/LICENSE.md" % animal)
		assert_str(licence).contains("CC0")
		assert_str(licence).contains("Quaternius")


func test_the_player_plays_the_fox() -> void:
	var animal: Node = auto_free(load("res://scenes/player/animal.tscn").instantiate())
	var species := (animal.get_node("%MovementComponent") as MovementComponent).species
	assert_str(species.resource_path).is_equal("res://data/species/fox.tres")


## Name of the last tail bone (tail length differs between species).
func _tail_tip(model: Node3D) -> String:
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var tip := ""
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).begins_with("Tail"):
			tip = skeleton.get_bone_name(b)
	return tip
