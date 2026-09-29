## Tests for resting ([Rester] and the Rest state): places (open, shade, den), energy rates,
## the faster game clock and getting up.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const SETTINGS: RestSettings = preload("res://data/interaction/rest.tres")


## Shade source double.
class FakeShade:
	extends Node

	var shaded: bool = false

	func is_shaded(_position: Vector3) -> bool:
		return shaded


var _saved_scale: float


func before_test() -> void:
	_saved_scale = GameState.clock_scale


func after_test() -> void:
	GameState.clock_scale = _saved_scale


func _animal() -> Animal:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.position.y = 0.05
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var rester := _rester(animal)
	rester.shade_source = auto_free(FakeShade.new())
	return animal


func _rester(animal: Animal) -> Rester:
	return animal.get_node("%Rester") as Rester


func _needs(animal: Animal) -> NeedsComponent:
	return animal.get_node("%NeedsComponent") as NeedsComponent


func _state(animal: Animal) -> String:
	return String(animal.state_machine.current_state_name())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Energy gained over [param seconds] of holding R.
func _rest_gain(animal: Animal, seconds: float) -> float:
	var needs := _needs(animal)
	needs.set_value(&"energy", 20.0)
	_rester(animal).rest_held = true
	await _frames(2)
	var before := needs.value(&"energy")
	await get_tree().create_timer(seconds).timeout
	return needs.value(&"energy") - before


func test_rates_by_place() -> void:
	var settings := SETTINGS
	var rester := _rester(_animal())
	assert_float(rester.energy_rate(Rester.Place.OPEN)).is_equal(settings.energy_per_second)
	assert_float(rester.energy_rate(Rester.Place.SHADE)).is_equal_approx(
		settings.energy_per_second * 2.0, 1e-4
	)
	assert_float(rester.energy_rate(Rester.Place.DEN)).is_equal_approx(
		settings.energy_per_second * 3.0, 1e-4
	)


func test_holding_rest_lies_down_and_speeds_up_the_clock_only_while_resting() -> void:
	var animal := _animal()
	await _frames(30)
	assert_float(GameState.clock_scale).is_equal(1.0)
	_rester(animal).rest_held = true
	await _frames(3)
	assert_str(_state(animal)).is_equal("Rest")
	assert_float(GameState.clock_scale).is_equal(GameState.CLOCK.rest_scale)
	var minutes := GameState.game_minutes
	await get_tree().create_timer(0.5).timeout
	assert_float(GameState.game_minutes - minutes).is_greater(3.0)  # ≈ 5 game minutes
	_rester(animal).rest_held = false
	await _frames(3)
	assert_str(_state(animal)).is_equal("Idle")
	assert_float(GameState.clock_scale).is_equal(1.0)


func test_resting_recovers_energy_much_faster_than_standing() -> void:
	var animal := _animal()
	await _frames(30)
	var needs := _needs(animal)
	needs.set_value(&"energy", 20.0)
	await get_tree().create_timer(1.0).timeout
	var idle_gain := needs.value(&"energy") - 20.0
	var rest_gain := await _rest_gain(animal, 1.0)
	assert_float(rest_gain).is_greater(idle_gain * 10.0)
	var rate := SETTINGS.energy_per_second
	assert_float(rest_gain).is_between(rate * 0.85, rate * 1.25)


func test_shade_doubles_the_recovery() -> void:
	var animal := _animal()
	await _frames(30)
	var open_gain := await _rest_gain(animal, 1.0)
	_rester(animal).rest_held = false
	await _frames(3)
	(_rester(animal).shade_source as FakeShade).shaded = true
	assert_int(_rester(animal).place()).is_equal(Rester.Place.SHADE)
	var shade_gain := await _rest_gain(animal, 1.0)
	assert_float(shade_gain / open_gain).is_between(1.7, 2.3)


func test_resting_at_a_den_with_e() -> void:
	var animal := _animal()
	var den: Interactable = auto_free(Interactable.new())
	den.definition = load("res://data/interactions/den.tres")
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	den.add_child(shape)
	den.position = Vector3(0, 0.3, -1.0)
	add_child(den)
	await _frames(30)
	var interactor := animal.get_node("%Interactor") as Interactor
	assert_str(interactor.current_target().definition.prompt).is_equal("Rest by the log")
	interactor.interact_held = true
	interactor.request_interaction()
	await _frames(3)
	assert_str(_state(animal)).is_equal("Rest")
	assert_int(_rester(animal).place()).is_equal(Rester.Place.DEN)
	assert_float(GameState.clock_scale).is_equal(GameState.CLOCK.rest_scale)
	interactor.interact_held = false
	await _frames(3)
	assert_str(_state(animal)).is_equal("Idle")


func test_moving_gets_up() -> void:
	var animal := _animal()
	await _frames(30)
	_rester(animal).rest_held = true
	await _frames(3)
	animal.movement.move_input = Vector2(0, -1)
	await _frames(3)
	assert_str(_state(animal)).is_equal("Locomotion")
	assert_float(GameState.clock_scale).is_equal(1.0)
	animal.movement.move_input = Vector2.ZERO


func test_no_rest_in_the_air() -> void:
	var animal := _animal()
	await _frames(30)
	animal.movement.request_jump()
	await _frames(6)
	_rester(animal).rest_held = true
	await _frames(2)
	assert_str(_state(animal)).is_not_equal("Rest")
