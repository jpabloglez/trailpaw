## Tests for the settings menu: controls change the settings at once, key capture with
## conflicts and cancel, saving on close, and opening it from the main and pause menus.
extends GdUnitTestSuite

const TEST_PATH: String = "user://test_settings_menu.cfg"
const MAIN_SCENE: String = "res://scenes/main/main.tscn"

var _saved_path: String


func before_test() -> void:
	_saved_path = Settings.config_path
	Settings.config_path = TEST_PATH


func after_test() -> void:
	get_tree().paused = false
	Settings.restore_default_bindings()
	Settings.set_fov(70.0)
	Settings.set_volume(&"SFX", 1.0)
	Settings.config_path = _saved_path
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _menu() -> SettingsMenu:
	var menu: SettingsMenu = auto_free(SettingsMenu.new())
	add_child(menu)
	menu.open()
	return menu


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func test_controls_change_the_settings_at_once() -> void:
	var menu := _menu()
	(menu.control("Fov") as HSlider).value = 90.0
	assert_float(Settings.fov).is_equal(90.0)
	(menu.control("VolumeSFX") as HSlider).value = 0.4
	assert_float(Settings.volume(&"SFX")).is_equal_approx(0.4, 1e-4)
	assert_bool(menu.control("Quality") is OptionButton).is_true()
	assert_bool(menu.control("RestoreDefaults") is Button).is_true()


func test_capturing_a_new_key_for_an_action() -> void:
	var menu := _menu()
	menu.begin_capture(&"jump")
	assert_str((menu.control("Bind_jump") as Button).text).is_equal("Press a key…")
	menu.capture(_key(KEY_K))
	assert_str((menu.control("Bind_jump") as Button).text).is_equal("K")
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_K))).is_true()
	assert_str(menu.status_text()).is_empty()


func test_a_key_used_elsewhere_is_refused_with_a_note() -> void:
	var menu := _menu()
	menu.begin_capture(&"jump")
	menu.capture(_key(KEY_E))  # interact
	assert_str(menu.status_text()).is_equal("Already used by Interact")
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_SPACE))).is_true()


func test_escape_cancels_a_capture() -> void:
	var menu := _menu()
	menu.begin_capture(&"jump")
	menu._input(_key(KEY_ESCAPE))
	assert_str((menu.control("Bind_jump") as Button).text).is_equal("Space")
	assert_bool(InputMap.action_has_event(&"jump", _key(KEY_SPACE))).is_true()


func test_closing_saves_the_settings() -> void:
	var menu := _menu()
	var closed: Array[int] = [0]
	menu.closed.connect(func() -> void: closed[0] += 1)
	(menu.control("Fov") as HSlider).value = 77.0
	(menu.control("Done") as Button).pressed.emit()
	assert_bool(menu.visible).is_false()
	assert_int(closed[0]).is_equal(1)
	var config := ConfigFile.new()
	assert_int(config.load(TEST_PATH)).is_equal(OK)
	assert_float(float(config.get_value("graphics", "fov"))).is_equal(77.0)


func test_opens_from_the_main_menu_and_the_pause_menu() -> void:
	var save_dir := SaveSystem.save_dir
	SaveSystem.save_dir = "user://test_settings_flow"
	SaveSystem.erase()
	var flow: GameFlow = load(MAIN_SCENE).instantiate()
	flow.suppress_quit = true
	add_child(flow)
	var menu_settings := flow.menu().button("Settings")
	assert_bool(menu_settings.visible).is_true()
	menu_settings.pressed.emit()
	assert_bool(flow.settings_menu().visible).is_true()
	assert_bool(flow.menu().visible).is_false()
	flow.settings_menu().close()
	assert_bool(flow.menu().visible).is_true()
	flow.start_new_game(3)
	flow.pause_menu().open()
	flow.pause_menu().button("Settings").pressed.emit()
	assert_bool(flow.settings_menu().visible).is_true()
	assert_bool(flow.pause_menu().visible).is_false()
	flow.settings_menu().close()
	assert_bool(flow.pause_menu().visible).is_true()
	flow.free()
	SaveSystem.erase()
	SaveSystem.save_dir = save_dir
	FloatingOrigin.reset()
	get_tree().auto_accept_quit = true
