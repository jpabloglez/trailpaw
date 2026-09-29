## Integration tests for swimming: entering and leaving at the waterline, floating, speed.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const WATER: float = 0.0
const SLOPE_DEGREES: float = 8.0

var _animal: Animal
var _species: AnimalSpecies
var _states: Array[StringName] = []
var _depth_at_change: Dictionary = {}


func before_test() -> void:
	GameState.water_level = WATER
	# A long ramp descending towards -Z through the water surface (dry at +Z, deep at -Z).
	var ramp: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.5, 80)
	shape.shape = box
	ramp.add_child(shape)
	ramp.rotation_degrees.x = -SLOPE_DEGREES
	add_child(ramp)
	# A fixed camera looking along -Z makes the move input camera-relative, like in the game.
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.position = Vector3(0, 10, 40)
	camera.current = true
	_animal = auto_free(load(ANIMAL_SCENE).instantiate())
	_animal.position = Vector3(0, 1.8, 8)  # close to the waterline keeps the suite short
	add_child(_animal)
	_animal.get_node("%PlayerInput").set_physics_process(false)
	_species = _animal.movement.species
	_states = []
	_depth_at_change = {}
	_animal.state_machine.state_changed.connect(
		func(_from: StringName, to: StringName) -> void:
			_states.append(to)
			_depth_at_change[to] = _animal.movement.water_depth()
	)


func after_test() -> void:
	GameState.water_level = -INF


func _walk(direction: Vector2, frames: int) -> void:
	_animal.movement.move_input = direction
	for i in frames:
		await get_tree().physics_frame


func test_enters_and_leaves_swimming_at_the_waterline() -> void:
	await _walk(Vector2.ZERO, 30)
	await _walk(Vector2(0, -1), 330)  # downhill into the water
	assert_bool(_states.has(&"Swim")).is_true()
	assert_float(_depth_at_change[&"Swim"]).is_between(
		_species.swim_enter_depth, _species.swim_enter_depth + 0.15
	)
	await _walk(Vector2(0, 1), 420)  # back uphill onto land
	assert_str(String(_animal.state_machine.current_state_name())).is_not_equal("Swim")
	var exit_state: StringName = _states[_states.rfind(&"Swim") + 1]
	assert_float(_depth_at_change[exit_state]).is_less(_species.swim_exit_depth)


func test_floats_at_the_surface_slower_than_on_land() -> void:
	await _walk(Vector2(0, -1), 400)
	assert_str(String(_animal.state_machine.current_state_name())).is_equal("Swim")
	var max_speed := 0.0
	for i in 120:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, _animal.movement.horizontal_speed())
	var float_height := WATER - _species.float_depth
	assert_float(_animal.global_position.y).is_equal_approx(float_height, 0.08)
	assert_float(max_speed).is_less_equal(_species.trot_speed * _species.swim_speed_factor + 0.05)


func test_model_is_level_and_swim_animation_plays() -> void:
	await _walk(Vector2(0, -1), 400)
	for i in 60:
		await get_tree().physics_frame
	var aligner := _animal.get_node("%GroundAligner") as GroundAligner
	assert_float(absf(aligner.tilt.x)).is_less(deg_to_rad(1.0))
	var controller := _animal.get_node("%AnimationController") as AnimationController
	assert_str(String(controller.current_state())).is_equal("swim")


func test_species_that_cannot_swim_walks_along_the_bottom() -> void:
	var walker := _species.duplicate() as AnimalSpecies
	walker.swim_enter_depth = 0.0
	_animal.movement.species = walker
	await _walk(Vector2(0, -1), 330)
	assert_bool(_states.has(&"Swim")).is_false()
