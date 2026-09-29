## Tests for the soft consequences of critical needs: eased slowdown, tired idle and the
## [NeedsModel] effect queries (ADR-003).
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const EPSILON: float = 1e-4


func _animal_on_floor() -> Animal:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position.y = 0.2
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _needs(animal: Animal) -> NeedsComponent:
	return animal.get_node("%NeedsComponent") as NeedsComponent


## Advances the component by [param seconds] in 0.1 s steps without waiting in real time.
func _advance(needs: NeedsComponent, seconds: float) -> void:
	needs.set_process(false)
	for i in int(seconds * 10.0):
		needs._process(0.1)


# --- model queries ------------------------------------------------------------------------


func test_model_effects_follow_the_critical_needs() -> void:
	var needs := _needs(_animal_on_floor())
	var model := needs.model
	assert_float(model.critical_speed_factor()).is_equal(1.0)
	assert_bool(model.is_tired()).is_false()
	model.set_value(&"thirst", 10.0)
	assert_float(model.critical_speed_factor()).is_equal(0.85)
	assert_bool(model.is_tired()).is_false()
	model.set_value(&"energy", 10.0)
	assert_float(model.critical_speed_factor()).is_equal(0.8)  # the lowest factor wins
	assert_bool(model.is_tired()).is_true()
	assert_int(model.critical_count()).is_equal(2)


# --- slowdown -----------------------------------------------------------------------------


func test_critical_need_slows_movement_gradually() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"thirst", 10.0)
	var ease: float = needs.modifiers.speed_ease_per_second
	var previous := 1.0
	for i in 30:
		_advance(needs, 0.1)
		var now := animal.movement.speed_multiplier
		assert_float(previous - now).is_less_equal(ease * 0.1 + EPSILON)  # no jumps
		previous = now
	assert_float(animal.movement.speed_multiplier).is_equal_approx(0.85, EPSILON)
	_advance(needs, 5.0)
	assert_float(animal.movement.speed_multiplier).is_equal_approx(0.85, EPSILON)  # floor


func test_slowed_animal_runs_at_the_reduced_speed() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"energy", 10.0)
	_advance(needs, 3.0)
	animal.movement.move_input = Vector2(0, -1)
	animal.movement.sprint = true
	var top := 0.0
	for i in 150:
		await get_tree().physics_frame
		top = maxf(top, animal.movement.horizontal_speed())
	var run_speed: float = animal.movement.species.run_speed
	assert_float(top).is_less_equal(run_speed * 0.8 + 0.01)
	assert_float(top).is_greater(run_speed * 0.8 - 0.1)


func test_speed_returns_to_normal_when_needs_recover() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"hunger", 10.0)
	_advance(needs, 3.0)
	needs.model.refill_all()
	_advance(needs, 3.0)
	assert_float(animal.movement.speed_multiplier).is_equal(1.0)


# --- tired idle ---------------------------------------------------------------------------


func test_low_energy_blends_in_the_tired_idle() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	var tree := (animal.get_node("%AnimationController") as AnimationController).tree()
	await get_tree().process_frame
	assert_float(tree.get(AnimationController.TIRED_PARAM)).is_equal(0.0)
	needs.set_value(&"energy", 10.0)
	_advance(needs, 3.0)
	assert_float(needs.tiredness()).is_equal(1.0)
	await get_tree().process_frame
	assert_float(tree.get(AnimationController.TIRED_PARAM)).is_equal(1.0)
	needs.model.refill_all()
	_advance(needs, 3.0)
	await get_tree().process_frame
	assert_float(tree.get(AnimationController.TIRED_PARAM)).is_equal(0.0)


func test_other_needs_do_not_look_tired() -> void:
	var needs := _needs(_animal_on_floor())
	needs.set_value(&"thirst", 10.0)
	needs.set_value(&"hunger", 10.0)
	_advance(needs, 3.0)
	assert_float(needs.tiredness()).is_equal(0.0)


func test_tired_idle_loops_while_the_same_clip_stays_one_shot_for_sniff() -> void:
	var animal := _animal_on_floor()
	var controller := animal.get_node("%AnimationController") as AnimationController
	var player: AnimationPlayer = (
		animal.model_root.find_children("*", "AnimationPlayer", true, false)[0]
	)
	var library := player.get_animation_library(AnimationController.LIBRARY)
	var tired := controller.library_name(&"tired_idle")
	assert_str(tired).is_equal("Idle_2_HeadLow" + AnimationController.LOOP_SUFFIX)
	assert_int(library.get_animation(tired).loop_mode).is_equal(Animation.LOOP_LINEAR)
	var sniff := controller.library_name(&"sniff")
	assert_str(sniff).is_equal("Idle_2_HeadLow")
	assert_int(library.get_animation(sniff).loop_mode).is_equal(Animation.LOOP_NONE)
