## Smoke/integration tests for the movement sandbox scene.
extends GdUnitTestSuite

const SANDBOX_SCENE: String = "res://scenes/debug/movement_sandbox.tscn"
const WORLD_LAYER_BIT: int = 1

var _sandbox: Node3D


func before_test() -> void:
	_sandbox = auto_free(load(SANDBOX_SCENE).instantiate())
	add_child(_sandbox)


func _animal() -> Animal:
	return _sandbox.get_node("Animal") as Animal


func test_has_animal_and_camera_rig_following_it() -> void:
	var rig := _sandbox.get_node("CameraRig") as CameraRig
	assert_object(_animal()).is_not_null()
	assert_object(rig).is_not_null()
	assert_object(rig.target).is_same(_animal())


func test_animal_settles_on_the_floor() -> void:
	_animal().get_node("%PlayerInput").set_physics_process(false)
	for i in 60:
		await get_tree().physics_frame
	assert_bool(_animal().is_on_floor()).is_true()
	assert_str(String(_animal().state_machine.current_state_name())).is_equal("Idle")
	assert_float(_animal().global_position.y).is_between(-0.05, 0.2)


func test_ramps_cover_both_sides_of_the_slope_limit() -> void:
	var limit := _animal().movement.species.max_slope_degrees
	var walkable := 0
	var too_steep := 0
	for ramp: Node in _sandbox.get_node("Level/Ramps").get_children():
		if ramp is StaticBody3D:
			var angle := rad_to_deg((ramp as Node3D).rotation.x)
			if angle <= limit + 0.01:
				walkable += 1
			else:
				too_steep += 1
	assert_int(walkable).is_greater(0)
	assert_int(too_steep).is_greater(0)


func test_level_geometry_is_on_world_layer_only() -> void:
	var bodies := _sandbox.get_node("Level").find_children("*", "StaticBody3D", true, false)
	assert_int(bodies.size()).is_greater(10)
	for body: Node in bodies:
		assert_int((body as StaticBody3D).collision_layer).is_equal(WORLD_LAYER_BIT)
