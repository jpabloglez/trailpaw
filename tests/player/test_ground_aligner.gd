## Tests for [GroundAligner]: tilt maths, clamping, ramps, smoothing and upright capsule.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const HUSKY: String = "res://data/species/husky.tres"

var _species: AnimalSpecies


func before() -> void:
	_species = load(HUSKY)


func _heights(fl: float, fr: float, bl: float, br: float) -> PackedFloat32Array:
	return PackedFloat32Array([fl, fr, bl, br])


## Ramp rising towards -Z (the animal's forward) by [param degrees], plus a flat floor.
func _world_with_ramp(degrees: float) -> void:
	var ramp: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.5, 30)
	shape.shape = box
	ramp.add_child(shape)
	ramp.rotation_degrees.x = degrees
	add_child(ramp)


func _animal_at(pos: Vector3) -> Animal:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position = pos
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _aligner(animal: Animal) -> GroundAligner:
	return animal.get_node("%GroundAligner") as GroundAligner


func _settle(frames: int = 120) -> void:
	for i in frames:
		await get_tree().physics_frame


func test_flat_ground_gives_no_tilt() -> void:
	assert_vector(GroundAligner.tilt_from_heights(_heights(1, 1, 1, 1), _species)).is_equal(
		Vector2.ZERO
	)


func test_front_higher_pitches_nose_up_and_left_higher_rolls_left_up() -> void:
	var up := GroundAligner.tilt_from_heights(_heights(0.2, 0.2, 0, 0), _species)
	assert_float(up.x).is_equal_approx(atan2(0.2, 2.0 * _species.paw_half_length), 1e-5)
	assert_float(up.y).is_equal(0.0)
	var left := GroundAligner.tilt_from_heights(_heights(0.05, 0, 0.05, 0), _species)
	assert_float(left.y).is_greater(0.0)


func test_angles_are_clamped_to_the_species_limit() -> void:
	var limit := deg_to_rad(_species.max_tilt_degrees)
	var extreme := GroundAligner.tilt_from_heights(_heights(10, -10, 10, -10), _species)
	assert_float(absf(extreme.x)).is_less_equal(limit + 1e-6)
	assert_float(absf(extreme.y)).is_less_equal(limit + 1e-6)


func test_model_pitches_with_a_gentle_ramp() -> void:
	_world_with_ramp(15.0)
	var animal := _animal_at(Vector3(0, 1.0, 0))
	await _settle()
	var aligner := _aligner(animal)
	assert_float(rad_to_deg(aligner.tilt.x)).is_equal_approx(15.0, 3.0)
	assert_float(rad_to_deg(animal.model_root.rotation.x)).is_equal_approx(15.0, 3.0)


func test_steep_ramp_is_clamped_and_capsule_stays_upright() -> void:
	_world_with_ramp(40.0)
	var animal := _animal_at(Vector3(0, 2.0, 0))
	await _settle()
	assert_float(rad_to_deg(_aligner(animal).tilt.x)).is_less_equal(
		_species.max_tilt_degrees + 0.01
	)
	assert_float(animal.rotation.x).is_equal(0.0)
	assert_float(animal.rotation.z).is_equal(0.0)


func test_tilt_is_smoothed_not_snapped() -> void:
	_world_with_ramp(15.0)
	var animal := _animal_at(Vector3(0, 1.0, 0))
	var aligner := _aligner(animal)
	var biggest_step := 0.0
	var previous := aligner.tilt.x
	for i in 90:
		await get_tree().physics_frame
		biggest_step = maxf(biggest_step, absf(aligner.tilt.x - previous))
		previous = aligner.tilt.x
	var bound := (
		deg_to_rad(_species.max_tilt_degrees) * (1.0 - exp(-_species.tilt_smoothing / 60.0))
	)
	assert_float(biggest_step).is_less_equal(bound + 1e-4)


func test_level_mode_eases_back_to_flat() -> void:
	_world_with_ramp(15.0)
	var animal := _animal_at(Vector3(0, 1.0, 0))
	await _settle()
	_aligner(animal).level = true
	await _settle(120)
	assert_float(absf(_aligner(animal).tilt.x)).is_less(deg_to_rad(0.5))
