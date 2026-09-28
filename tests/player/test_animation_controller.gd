## Tests for [AnimationController]: model spawning, looped clip copies, anti-slide time scale,
## state mapping and one-shot actions.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const PLAYER_SPECIES: String = "res://data/species/fox.tres"  # the player species
const EPSILON: float = 1e-4

var _species: AnimalSpecies


func before() -> void:
	_species = load(PLAYER_SPECIES)


func _animal_on_floor() -> Animal:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position.y = 0.2
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _controller(animal: Animal) -> AnimationController:
	return animal.get_node("%AnimationController") as AnimationController


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# --- anti-slide time scale ------------------------------------------------------------


func test_time_scale_is_one_when_standing() -> void:
	assert_float(AnimationController.time_scale_for(0.0, _species)).is_equal(1.0)


func test_time_scale_matches_clip_speed_at_walk_and_trot() -> void:
	var walk_clip: float = _species.clip_ground_speeds["Walk"]
	var gallop_clip: float = _species.clip_ground_speeds["Gallop"]
	assert_float(AnimationController.time_scale_for(_species.walk_speed, _species)).is_equal_approx(
		minf(_species.walk_speed / walk_clip, _species.max_animation_time_scale), EPSILON
	)
	assert_float(AnimationController.time_scale_for(_species.trot_speed, _species)).is_equal_approx(
		minf(_species.trot_speed / gallop_clip, _species.max_animation_time_scale), EPSILON
	)


func test_time_scale_never_exceeds_the_cap() -> void:
	for i in 100:
		var speed := _species.run_speed * i / 99.0
		assert_float(AnimationController.time_scale_for(speed, _species)).is_less_equal(
			_species.max_animation_time_scale + EPSILON
		)


func test_paws_do_not_slide_while_trotting() -> void:
	# Apparent paw speed = clip ground speed × playback scale must equal the movement speed.
	var scale := AnimationController.time_scale_for(_species.trot_speed, _species)
	var apparent: float = _species.clip_ground_speeds["Gallop"] * scale
	assert_float(apparent).is_equal_approx(_species.trot_speed, 0.01)


# --- scene integration ----------------------------------------------------------------


func test_husky_model_replaces_the_placeholder_box() -> void:
	var animal := _animal_on_floor()
	assert_int(animal.model_root.get_child_count()).is_greater(0)
	assert_bool((animal.get_node("Body") as Node3D).visible).is_false()
	assert_bool(_controller(animal).tree().active).is_true()


func test_loops_are_set_on_copies_not_on_the_imported_clips() -> void:
	var animal := _animal_on_floor()
	var player: AnimationPlayer = (
		animal.model_root.find_children("*", "AnimationPlayer", true, false)[0]
	)
	var library := player.get_animation_library(AnimationController.LIBRARY)
	assert_int(library.get_animation("Walk").loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_int(library.get_animation("Gallop_Jump").loop_mode).is_equal(Animation.LOOP_NONE)
	# The imported clip itself stays untouched.
	assert_int(player.get_animation("Walk").loop_mode).is_equal(Animation.LOOP_NONE)


func test_blend_follows_speed() -> void:
	var animal := _animal_on_floor()
	await _frames(40)
	animal.movement.move_input = Vector2(0, -1)
	await _frames(90)
	var blend: float = _controller(animal).tree().get("parameters/locomotion/gait/blend_position")
	assert_float(blend).is_equal_approx(animal.movement.horizontal_speed(), 0.05)
	assert_float(blend).is_greater(3.0)


func test_jump_and_fall_states_drive_the_animation() -> void:
	var animal := _animal_on_floor()
	await _frames(40)
	var seen := {}
	animal.movement.request_jump()
	for i in 120:
		await get_tree().physics_frame
		seen[_controller(animal).current_state()] = true
	assert_bool(seen.has(&"jump")).is_true()
	assert_bool(seen.has(&"fall")).is_true()
	assert_str(String(_controller(animal).current_state())).is_equal("locomotion")


func test_one_shot_action_returns_to_locomotion() -> void:
	var animal := _animal_on_floor()
	await _frames(40)
	var controller := _controller(animal)
	controller.play_action(&"sniff")
	await _frames(20)
	assert_str(String(controller.current_state())).is_equal("sniff")
	var clip_length := (
		(animal.model_root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer)
		. get_animation("Idle_2_HeadLow")
		. length
	)
	await get_tree().create_timer(clip_length + 0.6).timeout
	assert_str(String(controller.current_state())).is_equal("locomotion")


func test_species_without_model_keeps_the_placeholder() -> void:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.get_node("%MovementComponent").species = load("res://data/species/placeholder.tres")
	add_child(animal)
	assert_int(animal.model_root.get_child_count()).is_equal(0)
	assert_bool((animal.get_node("Body") as Node3D).visible).is_true()
	assert_object(_controller(animal).tree()).is_null()
