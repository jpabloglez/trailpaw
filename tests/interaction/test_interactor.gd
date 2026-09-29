## Scene tests for [Interactor] and the Interact state with the fox and [Interactable] objects.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const ONCE := InteractionDefinition.Mode.ONCE
const HOLD := InteractionDefinition.Mode.HOLD


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
	animal.position.y = 0.05
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _definition(
	mode: InteractionDefinition.Mode, effects: Dictionary, prompt: String = "Test"
) -> InteractionDefinition:
	var definition := InteractionDefinition.new()
	definition.id = StringName(prompt.to_snake_case())
	definition.type = (
		InteractionDefinition.Type.EAT if mode == ONCE else InteractionDefinition.Type.DRINK
	)
	definition.prompt = prompt
	definition.mode = mode
	definition.animation = &"sniff"
	definition.duration = 0.5
	definition.food_kind = &"berries"
	definition.need_effects.assign(effects)
	return definition


func _interactable(definition: InteractionDefinition, at: Vector3) -> Interactable:
	var node: Interactable = auto_free(Interactable.new())
	node.definition = definition
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	node.add_child(shape)
	node.position = at
	add_child(node)
	return node


func _interactor(animal: Animal) -> Interactor:
	return animal.get_node("%Interactor") as Interactor


func _needs(animal: Animal) -> NeedsComponent:
	return animal.get_node("%NeedsComponent") as NeedsComponent


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _state(animal: Animal) -> String:
	return String(animal.state_machine.current_state_name())


# --- targeting ----------------------------------------------------------------------------


func test_finds_the_object_in_front() -> void:
	var animal := _animal_on_floor()
	_interactable(_definition(ONCE, {&"hunger": 20.0}, "Eat test"), Vector3(0, 0.3, -1.0))
	await _frames(20)
	var target := _interactor(animal).current_target()
	assert_object(target).is_not_null()
	assert_str(target.definition.prompt).is_equal("Eat test")


func test_prefers_the_closest_in_front() -> void:
	var animal := _animal_on_floor()
	_interactable(_definition(ONCE, {}, "Far"), Vector3(0, 0.3, -1.5))
	_interactable(_definition(ONCE, {}, "Near"), Vector3(0.1, 0.3, -0.7))
	await _frames(20)
	assert_str(_interactor(animal).current_target().definition.prompt).is_equal("Near")


func test_ignores_targets_behind_and_unavailable() -> void:
	var animal := _animal_on_floor()
	_interactable(_definition(ONCE, {}, "Behind"), Vector3(0, 0.3, 1.0))
	var used := _interactable(_definition(ONCE, {}, "Used"), Vector3(0, 0.3, -1.0))
	used.available = false
	await _frames(20)
	assert_object(_interactor(animal).current_target()).is_null()


func test_food_outside_the_diet_is_ignored() -> void:
	var animal := _animal_on_floor()
	var grass := _definition(ONCE, {&"hunger": 10.0}, "Graze")
	grass.food_kind = &"grass"
	_interactable(grass, Vector3(0, 0.3, -1.0))
	await _frames(20)
	assert_object(_interactor(animal).current_target()).is_null()  # the fox does not graze


func test_target_changes_are_signalled() -> void:
	var animal := _animal_on_floor()
	var changes: Array = []
	_interactor(animal).target_changed.connect(
		func(t: InteractionTarget) -> void: changes.append(t)
	)
	var node := _interactable(_definition(ONCE, {}, "A"), Vector3(0, 0.3, -1.0))
	await _frames(20)
	node.available = false
	await _frames(20)
	assert_int(changes.size()).is_equal(2)
	assert_object(changes[1]).is_null()


# --- performing ---------------------------------------------------------------------------


func test_once_effects_are_applied_exactly_once() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"hunger", 50.0)
	_interactable(_definition(ONCE, {&"hunger": 20.0}), Vector3(0, 0.3, -1.0))
	var performed: Array[int] = [0]
	var on_performed := func(_t: int, _id: StringName) -> void: performed[0] += 1
	EventBus.interaction_performed.connect(on_performed)
	await _frames(20)
	_interactor(animal).request_interaction()
	await _frames(5)
	assert_str(_state(animal)).is_equal("Interact")
	assert_float(needs.value(&"hunger")).is_less(51.0)  # nothing until the end
	await get_tree().create_timer(0.8).timeout
	assert_str(_state(animal)).is_equal("Idle")
	await get_tree().create_timer(0.8).timeout
	EventBus.interaction_performed.disconnect(on_performed)
	assert_int(performed[0]).is_equal(1)
	assert_float(needs.value(&"hunger")).is_between(69.5, 70.0)


func test_depleting_source_becomes_unavailable() -> void:
	var animal := _animal_on_floor()
	var definition := _definition(ONCE, {&"hunger": 10.0})
	definition.regrowth_minutes = 60.0
	var node := _interactable(definition, Vector3(0, 0.3, -1.0))
	await _frames(20)
	_interactor(animal).request_interaction()
	await get_tree().create_timer(0.9).timeout
	assert_bool(node.available).is_false()
	assert_object(_interactor(animal).current_target()).is_null()


func test_hold_applies_while_held_and_stops_on_release() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"thirst", 20.0)
	_interactable(_definition(HOLD, {&"thirst": 10.0}), Vector3(0, 0.3, -1.0))
	await _frames(20)
	var interactor := _interactor(animal)
	interactor.interact_held = true
	interactor.request_interaction()
	await get_tree().create_timer(1.0).timeout
	assert_str(_state(animal)).is_equal("Interact")
	var during := needs.value(&"thirst")
	assert_float(during).is_between(28.0, 31.0)  # ≈ 10 per second
	interactor.interact_held = false
	await _frames(3)
	assert_str(_state(animal)).is_equal("Idle")
	await get_tree().create_timer(0.5).timeout
	assert_float(needs.value(&"thirst")).is_less_equal(during + 0.3)


func test_hold_stops_when_the_needs_are_full() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"thirst", 97.0)
	_interactable(_definition(HOLD, {&"thirst": 10.0}), Vector3(0, 0.3, -1.0))
	await _frames(20)
	var interactor := _interactor(animal)
	interactor.interact_held = true
	interactor.request_interaction()
	await get_tree().create_timer(0.8).timeout
	assert_str(_state(animal)).is_equal("Idle")
	assert_float(needs.value(&"thirst")).is_greater(99.5)  # full, then the usual slow decay


func test_moving_cancels_without_effects() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"hunger", 50.0)
	_interactable(_definition(ONCE, {&"hunger": 20.0}), Vector3(0, 0.3, -1.0))
	await _frames(20)
	_interactor(animal).request_interaction()
	await _frames(10)
	animal.movement.move_input = Vector2(1, 0)
	await _frames(3)
	assert_str(_state(animal)).is_equal("Locomotion")
	animal.movement.move_input = Vector2.ZERO
	await get_tree().create_timer(0.8).timeout
	assert_float(needs.value(&"hunger")).is_less(51.0)


func test_no_interaction_without_a_target_or_in_the_air() -> void:
	var animal := _animal_on_floor()
	await _frames(20)
	_interactor(animal).request_interaction()
	await _frames(3)
	assert_str(_state(animal)).is_not_equal("Interact")
	_interactable(_definition(ONCE, {}), Vector3(0, 0.3, -1.0))
	await _frames(20)
	animal.movement.request_jump()
	await _frames(6)
	_interactor(animal).request_interaction()
	await _frames(3)
	assert_str(_state(animal)).is_not_equal("Interact")


func test_debug_line_names_the_target() -> void:
	var animal := _animal_on_floor()
	_interactable(_definition(ONCE, {}, "Eat test"), Vector3(0, 0.3, -1.0))
	await _frames(20)
	assert_str(_interactor(animal).get_debug_lines()[0]).contains("Eat test")
