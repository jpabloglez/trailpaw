## Tests for [NeedsVignette]: intensity follows the number of critical needs, eased.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const VIGNETTE_SCENE: String = "res://scenes/ui/needs_vignette.tscn"


func _setup() -> Array:
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var needs := animal.get_node("%NeedsComponent") as NeedsComponent
	needs.set_process(false)
	var vignette: NeedsVignette = auto_free(load(VIGNETTE_SCENE).instantiate())
	vignette.needs = needs
	add_child(vignette)
	vignette.set_process(false)
	return [needs, vignette]


func _advance(vignette: NeedsVignette, seconds: float) -> void:
	for i in int(seconds * 10.0):
		vignette._process(0.1)


func test_hidden_while_no_need_is_critical() -> void:
	var vignette: NeedsVignette = _setup()[1]
	_advance(vignette, 2.0)
	assert_float(vignette.intensity()).is_equal(0.0)
	assert_bool((vignette.get_node("%Rect") as ColorRect).visible).is_false()


func test_intensity_follows_the_critical_count() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var vignette: NeedsVignette = setup[1]
	needs.set_value(&"thirst", 10.0)
	_advance(vignette, 10.0)
	assert_float(vignette.intensity()).is_equal_approx(0.5, 1e-4)
	assert_bool((vignette.get_node("%Rect") as ColorRect).visible).is_true()
	needs.set_value(&"hunger", 10.0)
	needs.set_value(&"energy", 10.0)
	_advance(vignette, 10.0)
	assert_float(vignette.intensity()).is_equal_approx(1.0, 1e-4)  # capped
	needs.model.refill_all()
	_advance(vignette, 10.0)
	assert_float(vignette.intensity()).is_equal(0.0)


func test_the_edges_turn_frosty_while_too_cold() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var vignette: NeedsVignette = setup[1]
	var saved := [GameState.snow_line, GameState.current_biome, GameState.game_minutes]
	GameState.current_biome = &"mountains"
	GameState.game_minutes = 0.0
	GameState.snow_line = -100.0  # everything is snow
	assert_bool(needs.is_cold()).is_true()
	_advance(vignette, 10.0)
	assert_float(vignette.intensity()).is_equal_approx(vignette.settings.cold_intensity, 1e-4)
	assert_float(vignette.coldness()).is_equal(1.0)
	var material := (vignette.get_node("%Rect") as ColorRect).material as ShaderMaterial
	var tint: Color = material.get_shader_parameter(&"tint")
	assert_bool(tint.is_equal_approx(vignette.settings.cold_tint)).is_true()
	GameState.snow_line = INF  # down from the snow: it eases back
	_advance(vignette, 10.0)
	assert_float(vignette.intensity()).is_equal(0.0)
	assert_float(vignette.coldness()).is_equal(0.0)
	GameState.snow_line = saved[0]
	GameState.current_biome = saved[1]
	GameState.game_minutes = saved[2]


func test_intensity_eases_instead_of_jumping() -> void:
	var setup := _setup()
	var needs: NeedsComponent = setup[0]
	var vignette: NeedsVignette = setup[1]
	needs.set_value(&"thirst", 10.0)
	vignette._process(0.1)
	assert_float(vignette.intensity()).is_equal_approx(
		vignette.settings.fade_per_second * 0.1, 1e-4
	)


func test_settings_cap_the_target_at_one() -> void:
	var settings := load("res://data/ui/needs_vignette.tres") as NeedsVignetteSettings
	assert_float(settings.target_intensity(0)).is_equal(0.0)
	assert_float(settings.target_intensity(1)).is_equal(0.5)
	assert_float(settings.target_intensity(4)).is_equal(1.0)
