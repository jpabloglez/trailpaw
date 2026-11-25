## Tests for menus without a mouse: the first button takes the focus, B goes back or closes,
## LB / RB switch settings tabs, and stick motion counts as one press per push.
extends GdUnitTestSuite

const TEST_PATH: String = "user://test_gamepad_menus.cfg"

var _saved_path: String


func before_test() -> void:
	_saved_path = Settings.config_path
	Settings.config_path = TEST_PATH


func after_test() -> void:
	InputDevice.set_gamepad(false)  # pad events in other suites switch it
	get_tree().paused = false
	Settings.config_path = _saved_path
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


func _stick(value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	return event


func test_focus_first_skips_hidden_and_disabled_buttons() -> void:
	var box: VBoxContainer = auto_free(VBoxContainer.new())
	add_child(box)
	var hidden := Button.new()
	hidden.visible = false
	var disabled := Button.new()
	disabled.disabled = true
	var label := Label.new()
	var usable := Button.new()
	usable.name = "Usable"
	for child: Control in [hidden, disabled, label, usable]:
		box.add_child(child)
	assert_bool(MenuStyle.focus_first(box)).is_true()
	assert_object(_focused()).is_same(usable)
	usable.visible = false
	usable.release_focus()
	assert_bool(MenuStyle.focus_first(box)).is_false()


func test_a_stick_push_is_one_press_until_it_comes_back() -> void:
	var stick := StickPress.new()
	var presses := 0
	for value in [0.6, 0.7, 0.9, 1.0, 0.0, 0.8, 0.9]:
		presses += int(stick.pressed(_stick(value), &"ui_right"))
	assert_int(presses).is_equal(2)
	assert_bool(stick.pressed(_stick(-1.0), &"ui_right")).is_false()
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	assert_bool(stick.pressed(key, &"ui_right")).is_true()


func test_shoulder_step() -> void:
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb.pressed = true
	assert_int(MenuStyle.shoulder_step(lb)).is_equal(-1)
	lb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	assert_int(MenuStyle.shoulder_step(lb)).is_equal(1)
	lb.pressed = false
	assert_int(MenuStyle.shoulder_step(lb)).is_equal(0)


func test_the_pause_menu_focuses_resume_and_b_resumes() -> void:
	var pause: PauseMenu = auto_free(PauseMenu.new())
	add_child(pause)
	pause.enabled = true
	pause.open()
	assert_object(_focused()).is_same(pause.button("Resume"))
	await _pad(JOY_BUTTON_B)
	assert_bool(pause.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_main_menu_focuses_each_page_and_b_goes_back() -> void:
	var menu: MainMenu = auto_free(MainMenu.new())
	add_child(menu)
	var first := "Continue" if SaveSystem.exists() else "NewGame"
	assert_object(_focused()).is_same(menu.button(first))
	menu.show_new_game()
	assert_object(_focused()).is_same(menu.button("Start"))
	await _pad(JOY_BUTTON_B)
	assert_str(menu.page()).is_equal("main")
	assert_object(_focused()).is_same(menu.button(first))


func test_settings_focus_lb_rb_tabs_and_b_closes() -> void:
	var menu: SettingsMenu = auto_free(SettingsMenu.new())
	add_child(menu)
	menu.open()
	var tabs := menu.control("Tabs") as TabContainer
	assert_int(tabs.current_tab).is_equal(0)
	assert_object(_focused()).is_same(menu.control("Quality"))
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(tabs.current_tab).is_equal(1)
	assert_object(_focused()).is_same(menu.control("VolumeMaster"))
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)  # wraps round
	assert_int(tabs.current_tab).is_equal(tabs.get_tab_count() - 1)
	await _pad(JOY_BUTTON_B)
	assert_bool(menu.visible).is_false()


func test_b_cancels_a_capture_before_closing_settings() -> void:
	var menu: SettingsMenu = auto_free(SettingsMenu.new())
	add_child(menu)
	menu.open()
	menu.begin_capture(&"jump")
	await _pad(JOY_BUTTON_B)
	assert_bool(menu.visible).is_true()
	assert_str((menu.control("Bind_jump") as Button).text).is_equal("Space")
	await _pad(JOY_BUTTON_B)
	assert_bool(menu.visible).is_false()
