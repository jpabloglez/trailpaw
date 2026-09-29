## Tests for drinking and cooling off ([WaterAccess]) in a pool with a shore (z > 0, ground 0),
## a shallow shelf (−3 < z < 0, ground −0.3) and deep water (z < −3, ground −1.5); the water
## surface is at −0.1.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const WATER_LEVEL: float = -0.1

var _saved_water: float


func before_test() -> void:
	_saved_water = GameState.water_level
	GameState.water_level = WATER_LEVEL


func after_test() -> void:
	GameState.water_level = _saved_water


func _slab(center_z: float, depth: float, top: float) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, depth)
	shape.shape = box
	shape.position = Vector3(0, top - 0.5, center_z)
	body.add_child(shape)
	add_child(body)


func _animal_at(z: float, ground: float) -> Animal:
	_slab(5.0, 10.0, 0.0)
	_slab(-1.5, 3.0, -0.3)
	_slab(-13.0, 20.0, -1.5)
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position = Vector3(0, ground + 0.05, z)
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	return animal


func _settle(n: int = 30) -> void:
	for i in n:
		await get_tree().physics_frame


func _target(animal: Animal) -> InteractionTarget:
	var interactor := animal.get_node("%Interactor") as Interactor
	interactor.probe()
	return interactor.current_target()


func _needs(animal: Animal) -> NeedsComponent:
	return animal.get_node("%NeedsComponent") as NeedsComponent


func _start_holding(animal: Animal) -> Interactor:
	var interactor := animal.get_node("%Interactor") as Interactor
	interactor.interact_held = true
	interactor.request_interaction()
	return interactor


func test_drink_at_the_shore_but_not_inland() -> void:
	var animal := _animal_at(0.5, 0.0)
	await _settle()
	var target := _target(animal)
	assert_object(target).is_not_null()
	assert_int(target.definition.type).is_equal(InteractionDefinition.Type.DRINK)
	animal.global_position.z = 4.0  # walk inland
	await _settle(10)
	assert_object(_target(animal)).is_null()


func test_no_water_targets_while_swimming() -> void:
	var animal := _animal_at(-8.0, -1.5)
	await _settle(90)
	assert_str(String(animal.state_machine.current_state_name())).is_equal("Swim")
	assert_object(_target(animal)).is_null()


func test_holding_drinks_at_the_defined_rate_and_release_stops() -> void:
	var animal := _animal_at(0.5, 0.0)
	await _settle()
	var needs := _needs(animal)
	needs.set_value(&"thirst", 20.0)
	var interactor := _start_holding(animal)
	await get_tree().create_timer(1.0).timeout
	var drunk := needs.value(&"thirst")
	var rate: float = load("res://data/interactions/drink.tres").need_effects[&"thirst"]
	assert_float(drunk).is_between(20.0 + rate * 0.85, 20.0 + rate * 1.1)
	interactor.interact_held = false
	await _settle(5)
	assert_str(String(animal.state_machine.current_state_name())).is_equal("Idle")
	await get_tree().create_timer(0.5).timeout
	assert_float(needs.value(&"thirst")).is_less_equal(drunk + 0.2)


func test_drinking_stops_full_and_never_exceeds_the_maximum() -> void:
	var animal := _animal_at(0.5, 0.0)
	await _settle()
	var needs := _needs(animal)
	needs.set_value(&"thirst", 95.0)
	_start_holding(animal)
	await get_tree().create_timer(1.0).timeout
	assert_float(needs.value(&"thirst")).is_between(99.5, 100.0)
	assert_str(String(animal.state_machine.current_state_name())).is_equal("Idle")


func test_cool_off_only_while_wading_and_much_faster_than_passive_cooling() -> void:
	var shore := _animal_at(0.5, 0.0)
	await _settle()
	var needs := _needs(shore)
	needs.set_value(&"temperature", 30.0)
	assert_int(_target(shore).definition.type).is_not_equal(InteractionDefinition.Type.COOL_OFF)
	shore.global_position = Vector3(0, -0.25, -1.5)  # into the shallows
	await _settle()
	var target := _target(shore)
	assert_int(target.definition.type).is_equal(InteractionDefinition.Type.COOL_OFF)
	_start_holding(shore)
	await get_tree().create_timer(1.0).timeout
	var gained := needs.value(&"temperature") - 30.0
	var passive := (
		1.5 * (load("res://data/needs/temperature.tres") as NeedDefinition).decay_per_minute
	)
	assert_float(gained).is_greater(passive / 60.0 * 10.0)  # ≥ 10× the passive water cooling


func test_wading_offers_the_lower_need() -> void:
	var animal := _animal_at(-1.5, -0.3)
	await _settle()
	var needs := _needs(animal)
	needs.set_value(&"temperature", 30.0)
	needs.set_value(&"thirst", 90.0)
	assert_int(_target(animal).definition.type).is_equal(InteractionDefinition.Type.COOL_OFF)
	needs.set_value(&"temperature", 90.0)
	needs.set_value(&"thirst", 30.0)
	assert_int(_target(animal).definition.type).is_equal(InteractionDefinition.Type.DRINK)


func test_a_drink_is_not_cut_short_when_cooling_off_becomes_the_better_offer() -> void:
	var animal := _animal_at(-1.5, -0.3)
	await _settle()
	var needs := _needs(animal)
	needs.set_value(&"temperature", 60.0)
	needs.set_value(&"thirst", 40.0)
	_start_holding(animal)
	await get_tree().create_timer(2.0).timeout  # thirst passes 60 while drinking
	assert_str(String(animal.state_machine.current_state_name())).is_equal("Interact")
	assert_float(needs.value(&"thirst")).is_greater(60.0)
