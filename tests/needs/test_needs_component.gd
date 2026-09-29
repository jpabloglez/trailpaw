## Scene tests for [NeedsComponent] on the player animal: 4 Hz tick, activity detection, biome
## warmth, water and EventBus relays.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"

var _saved_biome: StringName
var _saved_water: float


func before_test() -> void:
	_saved_biome = GameState.current_biome
	_saved_water = GameState.water_level


func after_test() -> void:
	GameState.current_biome = _saved_biome
	GameState.water_level = _saved_water


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


func _needs(animal: Animal) -> NeedsComponent:
	return animal.get_node("%NeedsComponent") as NeedsComponent


func test_the_animal_has_the_four_needs() -> void:
	var animal := _animal_on_floor()
	assert_array(_needs(animal).model.ids()).contains_exactly(
		[&"hunger", &"thirst", &"temperature", &"energy"]
	)


func test_ticks_at_four_hz() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	var ticks: Array[int] = [0]
	needs.need_changed.connect(
		func(id: StringName, _v: float) -> void: ticks[0] += 1 if id == &"hunger" else 0
	)
	await get_tree().create_timer(1.1).timeout
	assert_int(ticks[0]).is_between(4, 5)


func test_activity_follows_movement() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	await get_tree().create_timer(0.3).timeout
	assert_int(needs.activity()).is_equal(NeedsModel.Activity.IDLE)
	animal.movement.move_input = Vector2(0, -1)
	animal.movement.sprint = true
	await get_tree().create_timer(2.0).timeout
	assert_int(needs.activity()).is_equal(NeedsModel.Activity.RUN)
	animal.movement.swimming = true
	assert_int(needs.activity()).is_equal(NeedsModel.Activity.SWIM)
	animal.movement.swimming = false


func test_uses_the_current_biome_warmth() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	GameState.current_biome = &"hills"
	assert_float(needs.biome_warmth()).is_equal(1.0)
	GameState.current_biome = &"forest"
	assert_float(needs.biome_warmth()).is_less(0.0)
	GameState.current_biome = &"nowhere"
	assert_float(needs.biome_warmth()).is_equal(0.0)


func test_standing_in_water_cools_off() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	GameState.current_biome = &"hills"
	needs.set_value(&"temperature", 50.0)
	GameState.water_level = animal.global_position.y + 0.1  # wading
	needs.tick(60.0)
	assert_float(needs.value(&"temperature")).is_greater(50.0)


func test_critical_and_recovery_reach_the_event_bus() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	var events: Array = []
	var on_critical := func(id: StringName) -> void: events.append(["critical", id])
	var on_recovered := func(id: StringName) -> void: events.append(["recovered", id])
	EventBus.need_critical.connect(on_critical)
	EventBus.need_recovered.connect(on_recovered)
	needs.set_value(&"thirst", 10.0)
	needs.set_value(&"thirst", 90.0)
	EventBus.need_critical.disconnect(on_critical)
	EventBus.need_recovered.disconnect(on_recovered)
	assert_array(events).contains_exactly([["critical", &"thirst"], ["recovered", &"thirst"]])


func test_refill_action_fills_every_need() -> void:
	var animal := _animal_on_floor()
	var needs := _needs(animal)
	needs.set_value(&"hunger", 5.0)
	needs.set_value(&"energy", 5.0)
	var press := InputEventAction.new()
	press.action = &"debug_refill_needs"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(needs.value(&"hunger")).is_equal(100.0)
	assert_float(needs.value(&"energy")).is_equal(100.0)


func test_debug_lines_list_the_needs() -> void:
	var animal := _animal_on_floor()
	var lines := _needs(animal).get_debug_lines()
	assert_str(lines[0]).contains("thirst 100")
	assert_str(lines[0]).contains("idle")
