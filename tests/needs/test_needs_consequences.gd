## Tests for what low and empty needs do to the animal through [NeedsComponent] (ADR-012 on
## top of ADR-003): eased speed, the feeling-well bonus, sprint bursts and blocks, lower jumps
## and the tired idle.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const EPSILON: float = 1e-4

var _blocked: Array = []


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
	_blocked = []
	_needs(animal).effect_blocked.connect(
		func(id: StringName, ability: StringName) -> void: _blocked.append([id, ability])
	)
	return animal


func _needs(animal: Animal) -> NeedsComponent:
	return animal.get_node("%NeedsComponent") as NeedsComponent


## Advances the component by [param seconds] in 0.1 s steps without waiting in real time.
func _advance(needs: NeedsComponent, seconds: float) -> void:
	needs.set_process(false)
	for i in roundi(seconds * 10.0):
		needs._process(0.1)


## Keeps the needs where they are while time passes (no decay in these tests).
func _hold(needs: NeedsComponent, values: Dictionary, seconds: float) -> void:
	for i in roundi(seconds * 10.0):
		for id: StringName in values:
			needs.set_value(id, values[id])
		_advance(needs, 0.1)


func _sprint(animal: Animal, on: bool) -> void:
	animal.movement.move_input = Vector2(0, -1) if on else Vector2.ZERO
	animal.movement.sprint = on


# --- speed --------------------------------------------------------------------------------


func test_full_needs_feel_well_and_go_a_little_faster() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	_advance(needs, 2.0)
	assert_bool(needs.effects.feeling_well).is_true()
	assert_float(animal.movement.speed_multiplier).is_equal_approx(
		needs.effect_table.bonus_speed_factor, EPSILON
	)


func test_heat_slows_movement_gradually() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"hunger", 50.0)  # no bonus: starts at 1
	_advance(needs, 1.0)
	needs.set_value(&"temperature", 15.0)
	var ease: float = needs.modifiers.speed_ease_per_second
	var previous := animal.movement.speed_multiplier
	for i in 20:
		_hold(needs, {&"temperature": 15.0}, 0.1)
		var now := animal.movement.speed_multiplier
		assert_float(previous - now).is_less_equal(ease * 0.1 + EPSILON)  # no jumps
		previous = now
	assert_float(animal.movement.speed_multiplier).is_equal_approx(0.9, EPSILON)


func test_middling_needs_do_not_slow() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	_hold(needs, {&"thirst": 50.0, &"hunger": 50.0}, 2.0)
	assert_float(animal.movement.speed_multiplier).is_equal_approx(1.0, EPSILON)


func test_speed_returns_when_needs_recover() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	_hold(needs, {&"temperature": 15.0}, 3.0)
	needs.model.refill_all()
	_advance(needs, 3.0)
	assert_float(animal.movement.speed_multiplier).is_equal_approx(
		needs.effect_table.bonus_speed_factor, EPSILON
	)


func test_feeling_well_runs_past_the_run_speed() -> void:
	var animal := _animal_on_floor()
	_advance(_needs(animal), 2.0)
	_sprint(animal, true)
	var top := 0.0
	for i in 150:
		await get_tree().physics_frame
		top = maxf(top, animal.movement.horizontal_speed())
	var run_speed: float = animal.movement.species.run_speed
	assert_float(top).is_greater(run_speed + 0.1)
	assert_float(top).is_less_equal(run_speed * 1.05 + 0.01)


# --- sprinting ----------------------------------------------------------------------------


func test_empty_energy_trots_instead_of_running() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	_hold(needs, {&"energy": 0.0}, 3.0)
	_sprint(animal, true)
	var top := 0.0
	for i in 150:
		await get_tree().physics_frame
		needs.set_value(&"energy", 0.0)
		top = maxf(top, animal.movement.horizontal_speed())
	var trot_speed: float = animal.movement.species.trot_speed
	assert_bool(animal.movement.sprint_allowed).is_false()
	assert_float(top).is_less_equal(trot_speed * 0.9 + 0.01)
	assert_float(top).is_greater(trot_speed * 0.9 - 0.1)


func test_low_thirst_sprints_in_bursts() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	var table := needs.effect_table
	_hold(needs, {&"thirst": 20.0}, 0.5)
	_sprint(animal, true)
	_hold(needs, {&"thirst": 20.0}, table.burst_seconds - 0.5)
	assert_bool(animal.movement.sprint_allowed).is_true()
	assert_array(_blocked).is_empty()
	_hold(needs, {&"thirst": 20.0}, 0.6)
	assert_bool(animal.movement.sprint_allowed).is_false()  # catching its breath
	assert_array(_blocked).is_equal([[&"thirst", &"sprint"]])
	_hold(needs, {&"thirst": 20.0}, table.burst_rest_seconds + 0.2)
	assert_bool(animal.movement.sprint_allowed).is_true()
	assert_array(_blocked).has_size(1)


func test_empty_thirst_blocks_once_per_attempt() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	_hold(needs, {&"thirst": 0.0}, 0.5)
	_sprint(animal, true)
	_hold(needs, {&"thirst": 0.0}, 2.0)
	assert_array(_blocked).is_equal([[&"thirst", &"sprint"]])
	_sprint(animal, false)
	_hold(needs, {&"thirst": 0.0}, 0.3)
	_sprint(animal, true)
	_hold(needs, {&"thirst": 0.0}, 0.3)
	assert_array(_blocked).has_size(2)


func test_blocks_reach_the_event_bus() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	var heard: Array = []
	var listener := func(id: StringName, _ability: StringName) -> void: heard.append(id)
	EventBus.need_effect_blocked.connect(listener)
	_hold(needs, {&"energy": 0.0}, 0.5)
	_sprint(animal, true)
	_hold(needs, {&"energy": 0.0}, 0.5)
	EventBus.need_effect_blocked.disconnect(listener)
	assert_array(heard).is_equal([&"energy"])


func test_walking_without_sprint_is_never_blocked() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	animal.movement.move_input = Vector2(0, -1)
	_hold(needs, {&"thirst": 0.0, &"energy": 0.0, &"hunger": 0.0}, 2.0)
	assert_array(_blocked).is_empty()


# --- jumping ------------------------------------------------------------------------------


func test_empty_energy_jumps_lower() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	_advance(needs, 0.5)
	assert_float(animal.movement.jump_multiplier).is_equal(1.0)
	_hold(needs, {&"energy": 0.0}, 0.5)
	assert_float(animal.movement.jump_multiplier).is_equal(0.5)
	needs.model.refill_all()
	_advance(needs, 0.5)
	assert_float(animal.movement.jump_multiplier).is_equal(1.0)


func test_a_lower_jump_reaches_a_lower_apex() -> void:
	var animal := _animal_on_floor()
	for i in 20:
		await get_tree().physics_frame
	animal.movement.jump_multiplier = 0.5
	animal.movement.perform_jump()
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var height := pow(animal.movement.vertical_speed(), 2.0) / (2.0 * gravity)
	assert_float(height).is_equal_approx(animal.movement.species.jump_height * 0.5, 0.01)


# --- tired idle ---------------------------------------------------------------------------


func test_low_energy_blends_in_the_tired_idle() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	var tree := (animal.get_node("%AnimationController") as AnimationController).tree()
	await get_tree().process_frame
	assert_float(tree.get(AnimationController.TIRED_PARAM)).is_equal(0.0)
	_hold(needs, {&"energy": 10.0}, 3.0)
	assert_float(needs.tiredness()).is_equal(1.0)
	await get_tree().process_frame
	assert_float(tree.get(AnimationController.TIRED_PARAM)).is_equal(1.0)
	needs.model.refill_all()
	_advance(needs, 3.0)
	await get_tree().process_frame
	assert_float(tree.get(AnimationController.TIRED_PARAM)).is_equal(0.0)


func test_other_needs_do_not_look_tired() -> void:
	var needs := _needs(_animal_on_floor())
	_hold(needs, {&"thirst": 10.0, &"hunger": 10.0}, 3.0)
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
