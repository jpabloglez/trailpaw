## Tests for [NeedsHud] and [NeedMeter]: ring fraction, fade when full, pulse when critical,
## following the needs, and the code-drawn [NeedIcon] shapes.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const HUD_SCENE: String = "res://scenes/ui/needs_hud.tscn"
const IDS: Array[StringName] = [&"hunger", &"thirst", &"temperature", &"energy"]


func _setup() -> Array:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var needs := animal.get_node("%NeedsComponent") as NeedsComponent
	needs.set_process(false)
	var hud: NeedsHud = auto_free(load(HUD_SCENE).instantiate())
	hud.needs = needs
	add_child(hud)
	for id in IDS:
		hud.meter(id).set_process(false)
	return [needs, hud]


func _advance(meter: NeedMeter, seconds: float) -> void:
	for i in int(seconds * 10.0):
		meter.advance(0.1)


func test_one_meter_per_need_in_order() -> void:
	var hud: NeedsHud = _setup()[1]
	var row := hud.get_node("%Row")
	assert_int(row.get_child_count()).is_equal(4)
	for i in IDS.size():
		assert_object(row.get_child(i)).is_same(hud.meter(IDS[i]))


func test_ring_fraction_is_value_over_max() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var hud: NeedsHud = setup[1]
	needs.set_value(&"thirst", 62.0)
	assert_float(hud.meter(&"thirst").fraction()).is_equal_approx(0.62, 1e-5)
	needs.set_value(&"thirst", 0.0)
	assert_float(hud.meter(&"thirst").fraction()).is_equal(0.0)


func test_full_meters_start_hidden() -> void:
	var hud: NeedsHud = _setup()[1]
	for id in IDS:
		assert_float(hud.meter(id).opacity()).is_equal(0.0)


func test_meter_appears_when_the_need_drops_and_fades_after_the_hold_when_full() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var meter: NeedMeter = (setup[1] as NeedsHud).meter(&"hunger")
	needs.set_value(&"hunger", 70.0)
	_advance(meter, 1.0)
	assert_float(meter.opacity()).is_equal(1.0)
	needs.set_value(&"hunger", 100.0)
	_advance(meter, meter.settings.full_hold - 0.2)
	assert_float(meter.opacity()).is_equal(1.0)  # still holding
	_advance(meter, 1.5)
	assert_float(meter.opacity()).is_equal(0.0)


func test_fading_is_gradual() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var meter: NeedMeter = (setup[1] as NeedsHud).meter(&"energy")
	needs.set_value(&"energy", 50.0)
	meter.advance(0.1)
	assert_float(meter.opacity()).is_equal_approx(meter.settings.fade_per_second * 0.1, 1e-4)


func test_only_critical_meters_pulse() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var hud: NeedsHud = setup[1]
	needs.set_value(&"thirst", 10.0)
	needs.set_value(&"hunger", 50.0)
	var seen := 0.0
	for i in 20:
		hud.meter(&"thirst").advance(0.1)
		hud.meter(&"hunger").advance(0.1)
		seen = maxf(seen, hud.meter(&"thirst").pulse())
		assert_float(hud.meter(&"hunger").pulse()).is_equal(0.0)
	assert_float(seen).is_greater(0.3)
	assert_float(seen).is_less_equal(hud.meter(&"thirst").settings.pulse_amount + 1e-5)
	needs.set_value(&"thirst", 90.0)  # recovered
	assert_float(hud.meter(&"thirst").pulse()).is_equal(0.0)


func test_hud_follows_the_needs_tick() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var hud: NeedsHud = setup[1]
	needs.tick(60.0)  # a minute standing still
	for id in IDS:
		assert_float(hud.meter(id).fraction()).is_equal_approx(needs.model.fraction(id), 1e-5)


func test_every_need_has_a_distinct_icon() -> void:
	var shapes := {}
	for id in IDS:
		var need := load("res://data/needs/%s.tres" % id) as NeedDefinition
		assert_array(NeedIcon.SHAPES).contains([need.icon_shape])
		shapes[need.icon_shape] = true
	assert_int(shapes.size()).is_equal(IDS.size())


func test_icon_outlines_are_valid_polygons() -> void:
	for points in [
		NeedIcon.drop_points(10.0), NeedIcon.moon_points(10.0), NeedIcon.leaf_points(10.0)
	]:
		assert_int((points as PackedVector2Array).size()).is_greater(8)
		assert_bool(Geometry2D.triangulate_polygon(points).is_empty()).is_false()
		for p: Vector2 in points:
			assert_float(p.length()).is_less_equal(10.0 + 1e-3)
