## Tests for the six wild species: data, temperaments, model fit and orientation, relative
## sizes, credits and the agent's collision capsule.
extends GdUnitTestSuite

const TEMPERAMENTS: Dictionary = {
	&"deer": FaunaSpecies.Temperament.SHY,
	&"stag": FaunaSpecies.Temperament.SHY,
	&"shiba_inu": FaunaSpecies.Temperament.FRIENDLY,
	&"alpaca": FaunaSpecies.Temperament.CURIOUS,
	&"horse": FaunaSpecies.Temperament.CALM,
	&"donkey": FaunaSpecies.Temperament.CALM,
}


func _fauna(id: StringName) -> FaunaSpecies:
	return load("res://data/fauna/%s.tres" % id) as FaunaSpecies


func _placed(species: AnimalSpecies) -> Node3D:
	var model: Node3D = auto_free(species.model_scene.instantiate())
	model.scale = Vector3.ONE * species.model_scale
	model.rotation.y = deg_to_rad(species.model_yaw_degrees)
	add_child(model)
	return model


func _bone(model: Node3D, bone: String) -> Vector3:
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	)


func test_every_species_is_valid_with_the_chosen_temperament() -> void:
	for id: StringName in TEMPERAMENTS:
		var fauna := _fauna(id)
		assert_array(Array(fauna.get_validation_errors())).is_empty()
		assert_str(String(fauna.id)).is_equal(String(id))
		assert_int(fauna.temperament).is_equal(TEMPERAMENTS[id])
		assert_bool(fauna.animal.can_swim()).is_false()  # fauna keep out of water


func test_models_face_forward_stand_on_their_paws_and_match_their_body() -> void:
	for id: StringName in TEMPERAMENTS:
		var animal := _fauna(id).animal
		var model := _placed(animal)
		await get_tree().process_frame
		var head := _bone(model, "Head")
		var hips := _bone(model, "FFB.L")
		var message := String(id)
		assert_float(head.z).override_failure_message(message).is_less(hips.z)  # forward is -Z
		assert_float(_bone(model, "FF.L").y).override_failure_message(message).is_between(
			-0.06, 0.15
		)
		var length := absf(hips.z - head.z)
		assert_float(length).override_failure_message(message).is_between(
			animal.body_length * 0.55, animal.body_length * 1.4
		)


func test_relative_sizes_make_sense() -> void:
	var heights := {}
	for id: StringName in TEMPERAMENTS:
		var model := _placed(_fauna(id).animal)
		await get_tree().process_frame
		heights[id] = _bone(model, "Head").y
	assert_float(heights[&"horse"]).is_greater(heights[&"donkey"])
	assert_float(heights[&"donkey"]).is_greater(heights[&"shiba_inu"])
	assert_float(heights[&"stag"]).is_greater_equal(heights[&"deer"] * 0.95)
	for id: StringName in heights:
		assert_float(heights[id]).override_failure_message(String(id)).is_between(0.5, 2.6)


func test_walking_matches_the_clip_so_hooves_do_not_slide() -> void:
	for id: StringName in TEMPERAMENTS:
		var animal := _fauna(id).animal
		var clip: float = animal.clip_ground_speeds["Walk"]
		var scale := AnimationController.time_scale_for(animal.walk_speed, animal)
		assert_float(clip * scale).override_failure_message(String(id)).is_equal_approx(
			animal.walk_speed, 0.02
		)


func test_models_are_credited_with_their_licence() -> void:
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for id: StringName in TEMPERAMENTS:
		assert_str(credits).contains("assets/animals/%s/%s.glb" % [id, id])
		var licence := FileAccess.get_file_as_string("res://assets/animals/%s/LICENSE.md" % id)
		assert_str(licence).contains("CC0")
		assert_str(licence).contains("Quaternius")


func test_each_agent_gets_a_capsule_fitted_to_its_body() -> void:
	for id: StringName in TEMPERAMENTS:
		var fauna := _fauna(id)
		var agent: FaunaAgent = auto_free(load("res://scenes/fauna/fauna_agent.tscn").instantiate())
		agent.fauna = fauna
		add_child(agent)
		var capsule := (
			(agent.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
		)
		assert_float(capsule.radius).is_equal_approx(fauna.animal.body_radius, 1e-5)
		assert_float(capsule.height).is_equal_approx(fauna.animal.body_length, 1e-5)
		assert_int(agent.model_root.get_child_count()).is_greater(0)
