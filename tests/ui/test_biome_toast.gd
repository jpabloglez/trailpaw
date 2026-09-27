## Tests for [BiomeToast]: shows the biome name on the EventBus signal, then hides.
extends GdUnitTestSuite

const TOAST_SCENE: String = "res://scenes/ui/biome_toast.tscn"

var _toast: BiomeToast


func before_test() -> void:
	_toast = auto_free(load(TOAST_SCENE).instantiate())
	add_child(_toast)
	var fast := BiomeToastSettings.new()
	fast.fade_in = 0.05
	fast.hold = 0.05
	fast.fade_out = 0.05
	_toast.settings = fast


func test_default_timings_are_valid() -> void:
	var settings := load("res://data/ui/biome_toast.tres") as BiomeToastSettings
	assert_float(settings.total()).is_between(1.0, 10.0)
	assert_float(settings.hold).is_greater(settings.fade_in)


func test_hidden_until_a_biome_is_entered() -> void:
	assert_bool(_toast.visible).is_false()


func test_shows_the_display_name_from_the_event_then_hides() -> void:
	EventBus.biome_entered.emit(&"forest", "Forest")
	assert_bool(_toast.visible).is_true()
	assert_str(_toast.text()).is_equal("Forest")
	await get_tree().create_timer(_toast.settings.total() + 0.2).timeout
	assert_bool(_toast.visible).is_false()


func test_new_biome_mid_toast_restarts_with_new_name() -> void:
	_toast.show_text("Forest")
	await get_tree().create_timer(0.07).timeout
	_toast.show_text("River Valley")
	assert_str(_toast.text()).is_equal("River Valley")
	await get_tree().create_timer(0.1).timeout
	assert_bool(_toast.visible).is_true()  # the first toast's end no longer applies
	await get_tree().create_timer(0.2).timeout
	assert_bool(_toast.visible).is_false()
