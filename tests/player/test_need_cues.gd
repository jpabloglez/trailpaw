## Tests for [NeedCues]: panting, the hungry rumble and shivering follow the need cues, fade
## in and out, and leave the model as it was once they are gone (ADR-012).
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"


func _animal() -> Animal:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	_needs(animal).set_process(false)
	_cues(animal).set_process(false)
	return animal


func _needs(animal: Animal) -> NeedsComponent:
	return animal.get_node("%NeedsComponent") as NeedsComponent


func _cues(animal: Animal) -> NeedCues:
	return animal.get_node("%NeedCues") as NeedCues


func _feel(animal: Animal, values: Dictionary, cold := false) -> void:
	var needs := _needs(animal)
	for id: StringName in values:
		needs.set_value(id, values[id])
	needs.effects.update(needs.model, cold, false)


func _advance(cues: NeedCues, seconds: float) -> void:
	for i in roundi(seconds * 20.0):
		cues.advance(0.05)


func _model(animal: Animal) -> Node3D:
	return animal.model_root.get_child(0) as Node3D


func test_no_cues_with_needs_fine() -> void:
	var animal := _animal()
	var cues := _cues(animal)
	var scale := _model(animal).scale
	_advance(cues, 1.0)
	assert_float(cues.pant_weight()).is_equal(0.0)
	assert_float(cues.shiver_weight()).is_equal(0.0)
	assert_bool(cues.pant_player().playing).is_false()
	assert_vector(_model(animal).scale).is_equal(scale)


func test_thirst_pants_gradually_with_sound_and_breath() -> void:
	var animal := _animal()
	var cues := _cues(animal)
	var base := _model(animal).scale
	_feel(animal, {&"thirst": 10.0})
	_advance(cues, 0.2)
	assert_float(cues.pant_weight()).is_between(0.1, 0.5)  # fading in
	_advance(cues, 1.0)
	assert_float(cues.pant_weight()).is_equal(1.0)
	assert_bool(cues.pant_player().playing).is_true()
	var stream := cues.pant_player().stream as AudioStreamWAV
	assert_int(stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	var heights: Array[float] = []
	for i in 10:
		cues.advance(0.03)
		heights.append(_model(animal).scale.y / base.y)
	assert_float(heights.max() - heights.min()).is_greater(0.01)  # the chest rises and falls
	assert_float(_model(animal).scale.x).is_equal_approx(base.x, 1e-5)


func test_cues_fade_out_and_restore_the_model() -> void:
	var animal := _animal()
	var cues := _cues(animal)
	var scale := _model(animal).scale
	var rotation := _model(animal).rotation
	_feel(animal, {&"thirst": 10.0, &"temperature": 10.0}, true)
	_advance(cues, 1.0)
	assert_float(cues.shiver_weight()).is_equal(1.0)
	_needs(animal).model.refill_all()
	_feel(animal, {})
	_advance(cues, 1.0)
	assert_float(cues.pant_weight()).is_equal(0.0)
	assert_bool(cues.pant_player().playing).is_false()
	assert_vector(_model(animal).scale).is_equal(scale)
	assert_vector(_model(animal).rotation).is_equal(rotation)


func test_cold_shivers_without_panting() -> void:
	var animal := _animal()
	var cues := _cues(animal)
	var yaw := _model(animal).rotation.y
	_feel(animal, {&"temperature": 10.0}, true)
	var rolls: Array[float] = []
	for i in 40:
		cues.advance(0.05)
		rolls.append(_model(animal).rotation.z)
	assert_float(cues.pant_weight()).is_equal(0.0)
	assert_float(rolls.max() - rolls.min()).is_greater(deg_to_rad(1.0))
	assert_float(absf(rolls.max())).is_less_equal(deg_to_rad(cues.settings.shiver_degrees) + 1e-4)
	assert_float(_model(animal).rotation.y).is_equal_approx(yaw, 1e-5)  # still facing ahead


func test_hunger_rumbles_now_and_then() -> void:
	var animal := _animal()
	var cues := _cues(animal)
	var settings := cues.settings
	_feel(animal, {&"hunger": 10.0})
	_advance(cues, settings.growl_first - 0.5)
	assert_bool(cues.growl_player().playing).is_false()
	_advance(cues, 0.6)
	assert_bool(cues.growl_player().playing).is_true()
	cues.growl_player().stop()
	_advance(cues, settings.growl_every.x - 1.0)
	assert_bool(cues.growl_player().playing).is_false()  # not again too soon
	_advance(cues, settings.growl_every.y - settings.growl_every.x + 1.5)
	assert_bool(cues.growl_player().playing).is_true()
