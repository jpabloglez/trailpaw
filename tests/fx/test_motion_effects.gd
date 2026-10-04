## Tests for the movement effects ([MotionEffects]): dust when trotting on dry ground, nothing at
## a walk, splashes in water, a puff on a hard landing, a capped pool and the Low preset.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const SETTINGS: MotionEffectsSettings = preload("res://data/fx/motion_effects.tres")

var _saved_water: float
var _saved_quality: QualityPreset
var _saved_biome: StringName
var _started: Array[StringName] = []


func before_test() -> void:
	_saved_water = GameState.water_level
	_saved_quality = Settings.quality
	_saved_biome = GameState.current_biome
	GameState.water_level = -INF
	GameState.current_biome = &"meadow"
	_started.clear()


func after_test() -> void:
	GameState.water_level = _saved_water
	GameState.current_biome = _saved_biome
	Settings.set_quality(_saved_quality)


func _floor() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)


func _animal() -> Animal:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var effects := _effects(animal)
	effects.effect_started.connect(
		func(kind: StringName, _at: Vector3) -> void: _started.append(kind)
	)
	return animal


func _effects(animal: Animal) -> MotionEffects:
	return animal.get_node("%MotionEffects") as MotionEffects


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _at_speed(animal: Animal, speed: float) -> void:
	animal.movement._speed = speed  # as if moving (read in the same frame)


func test_trotting_on_dry_ground_raises_dust_tinted_by_the_biome() -> void:
	_floor()
	var animal := _animal()
	await _frames(20)
	_started.clear()
	_at_speed(animal, animal.movement.species.trot_speed)
	_effects(animal).on_footstep()
	assert_array(_started).contains_exactly([&"dust"])
	assert_int(_effects(animal).active_count()).is_equal(1)
	var emitter := _effects(animal).get_child(0) as GPUParticles3D
	var color := (emitter.process_material as ParticleProcessMaterial).color
	assert_bool(color.is_equal_approx(SETTINGS.dust_tint)).is_false()  # the meadow's ground
	assert_float(emitter.global_position.distance_to(animal.global_position)).is_less(0.2)


func test_walking_raises_nothing() -> void:
	_floor()
	var animal := _animal()
	await _frames(20)
	_started.clear()
	_at_speed(animal, animal.movement.species.walk_speed)
	_effects(animal).on_footstep()
	assert_array(_started).is_empty()


func test_steps_in_water_splash() -> void:
	_floor()
	var animal := _animal()
	await _frames(20)
	_started.clear()
	GameState.water_level = 0.3  # the paws are under water
	_at_speed(animal, animal.movement.species.walk_speed)
	_effects(animal).on_footstep()
	assert_array(_started).contains([&"splash"])


func test_a_hard_landing_raises_a_puff_and_a_soft_one_does_not() -> void:
	_floor()
	var animal := _animal()
	await _frames(20)
	_started.clear()
	animal.position.y = 0.3  # a small hop: lands slowly
	await _frames(40)
	assert_array(_started).is_empty()
	animal.position.y = 3.0  # a real fall
	await _frames(90)
	assert_array(_started).contains([&"landing"])


func test_the_pool_is_capped() -> void:
	_floor()
	var animal := _animal()
	await _frames(20)
	_at_speed(animal, animal.movement.species.run_speed)
	for i in SETTINGS.pool_size * 3:
		_effects(animal).on_footstep()
	assert_int(_effects(animal).get_child_count()).is_equal(SETTINGS.pool_size)
	assert_int(_effects(animal).active_count()).is_less_equal(SETTINGS.pool_size)


func test_the_low_preset_turns_them_off() -> void:
	_floor()
	var animal := _animal()
	await _frames(20)
	Settings.set_quality(load("res://data/quality/low.tres"))
	_started.clear()
	_at_speed(animal, animal.movement.species.run_speed)
	_effects(animal).on_footstep()
	assert_array(_started).is_empty()
	assert_int(_effects(animal).active_count()).is_equal(0)
