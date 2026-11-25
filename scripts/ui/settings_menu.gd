class_name SettingsMenu
extends CanvasLayer
## Settings with four tabs — Graphics, Audio, Controls, Interface — shared by the main menu and the
## pause menu. Every change applies at once through the [code]Settings[/code] autoload; closing
## saves them. Controls lists every remappable action with two buttons, keyboard/mouse and
## gamepad: click one, then press a key or mouse button (Esc cancels) or a pad button, trigger or
## stick direction (Esc or Menu cancels); an input used by another action is refused with a
## note. Built in code.
## [br][br]
## Without a mouse: the first control of the tab takes the focus, LB / RB switch tabs, and
## Esc or B cancels a capture or closes the menu.

## The menu was closed (settings saved).
signal closed

## Action → label shown to the player.
const ACTION_NAMES: Dictionary[StringName, String] = {
	&"move_forward": "Forward",
	&"move_back": "Back",
	&"move_left": "Left",
	&"move_right": "Right",
	&"sprint": "Run",
	&"jump": "Jump",
	&"interact": "Interact",
	&"sniff": "Sniff",
	&"rest": "Rest",
	&"camera_zoom_in": "Zoom in",
	&"camera_zoom_out": "Zoom out",
	&"map": "Map",
	&"journal": "Journal",
	&"pause": "Pause",
}
## Names of the fixed actions a rebinding may clash with.
const RESERVED_NAMES: Dictionary[StringName, String] = {
	&"camera_look_left": "Camera",
	&"camera_look_right": "Camera",
	&"camera_look_up": "Camera",
	&"camera_look_down": "Camera",
}
## Quality preset ids in menu order.
const QUALITY_IDS: Array[StringName] = [&"low", &"medium", &"high"]
## Text sizes offered (interface scale).
const UI_SCALES: Array[float] = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]

var _root: Control
var _tabs: TabContainer
var _status: Label
var _capturing: StringName = &""
var _capturing_pad: bool = false
var _binding_buttons: Dictionary[StringName, Button] = {}
var _pad_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var box := MenuStyle.centred_box(_root, "SettingsPage")
	box.add_child(MenuStyle.label("Settings", 36))
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.custom_minimum_size = Vector2(620, 420)
	box.add_child(_tabs)
	_tabs.add_child(_graphics_tab())
	_tabs.add_child(_audio_tab())
	_tabs.add_child(_controls_tab())
	_tabs.add_child(_interface_tab())
	_status = MenuStyle.label("", 18, "Status")
	box.add_child(_status)
	var done := MenuStyle.button("Done", "Done")
	done.pressed.connect(close)
	box.add_child(done)
	visible = false


func _input(event: InputEvent) -> void:
	if _capturing == &"" or not visible:
		return
	if _capturing_pad:
		_capture_pad_input(event)
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	var pressed := (
		(key != null and key.pressed and not key.echo) or (mouse != null and mouse.pressed)
	)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if key != null and key.physical_keycode == KEY_ESCAPE and _capturing != &"pause":
		_end_capture("")
		return
	capture(event)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _capturing != &"":
			_end_capture("")
		else:
			close()
		get_viewport().set_input_as_handled()
	elif _capturing == &"" and MenuStyle.shoulder_step(event) != 0:
		show_tab(posmod(_tabs.current_tab + MenuStyle.shoulder_step(event), _tabs.get_tab_count()))
		get_viewport().set_input_as_handled()


## Shows the menu with the current values.
func open() -> void:
	_refresh()
	_status.text = ""
	visible = true
	MenuStyle.fade_in(_root)
	show_tab(_tabs.current_tab)


## Shows tab [param index] (0 Graphics … 3 Interface) and focuses its first control.
func show_tab(index: int) -> void:
	_tabs.current_tab = index
	MenuStyle.focus_first(_tabs.get_current_tab_control())


## Saves the settings and hides the menu.
func close() -> void:
	_end_capture("")
	Settings.save_settings()
	visible = false
	closed.emit()


## Waits for the next key or mouse button for [param action] or, with [param gamepad], the
## next pad button, trigger or stick direction.
func begin_capture(action: StringName, gamepad: bool = false) -> void:
	_end_capture("")
	_capturing = action
	_capturing_pad = gamepad
	if gamepad:
		_pad_buttons[action].text = "Press a button…"
		var cancel := "Esc or Menu cancels" if action != &"pause" else "Esc cancels"
		_status.text = "Press a gamepad button for %s (%s)" % [ACTION_NAMES[action], cancel]
	else:
		_binding_buttons[action].text = "Press a key…"
		_status.text = "Press a key or mouse button for %s (Esc cancels)" % ACTION_NAMES[action]


## Binds the action being captured to [param event] (refused when another action uses it).
func capture(event: InputEvent) -> void:
	if _capturing == &"":
		return
	var conflict := Settings.rebind(_capturing, event)
	if conflict == &"":
		_end_capture("")
	elif conflict == &"?":
		_end_capture("That input cannot be used")
	else:
		var who: String = ACTION_NAMES.get(conflict, RESERVED_NAMES.get(conflict, String(conflict)))
		_end_capture("Already used by %s" % who)


## The control named [param node_name] (tests and tools).
func control(node_name: String) -> Control:
	return _root.find_child(node_name, true, false) as Control


## The note under the tabs.
func status_text() -> String:
	return _status.text


func _end_capture(note: String) -> void:
	if _capturing != &"" and _binding_buttons.has(_capturing):
		_show_bindings(_capturing)
	_capturing = &""
	_capturing_pad = false
	_status.text = note


# While waiting for a pad input every pad event is taken here (so B can be bound rather than
# cancel, and the sticks do not move the focus); Esc, or Menu (unless binding pause), cancels.
func _capture_pad_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null:
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_end_capture("")
		return
	if not InputBinding.is_gamepad(event):
		return
	get_viewport().set_input_as_handled()
	var button := event as InputEventJoypadButton
	if button != null and button.pressed:
		if button.button_index == JOY_BUTTON_START and _capturing != &"pause":
			_end_capture("")
		else:
			capture(event)
		return
	var motion := event as InputEventJoypadMotion
	if motion != null and absf(motion.axis_value) >= 0.5:
		capture(event)


func _show_bindings(action: StringName) -> void:
	_binding_buttons[action].text = InputBinding.action_text(action)
	var pad := InputBinding.action_text(action, true)
	_pad_buttons[action].text = pad if pad != "" else "—"


func _refresh() -> void:
	(control("Quality") as OptionButton).select(QUALITY_IDS.find(Settings.quality.id))
	(control("Fullscreen") as CheckBox).set_pressed_no_signal(Settings.fullscreen)
	(control("Resolution") as OptionButton).select(
		maxi(0, Settings.RESOLUTIONS.find(Settings.resolution))
	)
	(control("RenderScale") as HSlider).set_value_no_signal(Settings.render_scale)
	(control("VSync") as CheckBox).set_pressed_no_signal(Settings.vsync)
	(control("Fov") as HSlider).set_value_no_signal(Settings.fov)
	for bus in Settings.BUSES:
		(control("Volume" + String(bus)) as HSlider).set_value_no_signal(Settings.volume(bus))
	(control("Sensitivity") as HSlider).set_value_no_signal(Settings.mouse_sensitivity)
	(control("StickSensitivity") as HSlider).set_value_no_signal(Settings.stick_sensitivity)
	(control("InvertY") as CheckBox).set_pressed_no_signal(Settings.invert_y)
	(control("CameraShake") as CheckBox).set_pressed_no_signal(Settings.camera_shake)
	(control("MusicFrequency") as OptionButton).select(
		Settings.MUSIC_FREQUENCIES.find(Settings.music_frequency)
	)
	(control("SprintMode") as OptionButton).select(1 if Settings.sprint_toggle else 0)
	(control("RestMode") as OptionButton).select(1 if Settings.rest_toggle else 0)
	(control("ShowHints") as CheckBox).set_pressed_no_signal(Settings.hints.enabled)
	(control("TextSize") as OptionButton).select(
		maxi(0, UI_SCALES.find(snappedf(Settings.ui_scale, 0.1)))
	)
	for action: StringName in _binding_buttons:
		_show_bindings(action)


func _graphics_tab() -> Control:
	var grid := _tab("Graphics")
	var quality := OptionButton.new()
	quality.name = "Quality"
	for id in QUALITY_IDS:
		quality.add_item(String(id).capitalize())
	quality.item_selected.connect(
		func(i: int) -> void: Settings.set_quality(load(Settings.QUALITY_PATHS[QUALITY_IDS[i]]))
	)
	_row(grid, "Quality", quality)
	var fullscreen := CheckBox.new()
	fullscreen.name = "Fullscreen"
	fullscreen.toggled.connect(Settings.set_fullscreen)
	_row(grid, "Fullscreen", fullscreen)
	var resolution := OptionButton.new()
	resolution.name = "Resolution"
	for size in Settings.RESOLUTIONS:
		resolution.add_item("%d × %d" % [size.x, size.y])
	resolution.item_selected.connect(
		func(i: int) -> void: Settings.set_resolution(Settings.RESOLUTIONS[i])
	)
	_row(grid, "Window size", resolution)
	_row(grid, "Render scale", _slider("RenderScale", 0.5, 1.0, 0.05, Settings.set_render_scale))
	var vsync := CheckBox.new()
	vsync.name = "VSync"
	vsync.toggled.connect(Settings.set_vsync)
	_row(grid, "V-Sync", vsync)
	_row(grid, "Field of view", _slider("Fov", 50.0, 100.0, 1.0, Settings.set_fov))
	return grid.get_parent()


func _audio_tab() -> Control:
	var grid := _tab("Audio")
	for bus in Settings.BUSES:
		var slider := _slider(
			"Volume" + String(bus),
			0.0,
			1.0,
			0.05,
			func(v: float) -> void: Settings.set_volume(bus, v)
		)
		_row(grid, String(bus), slider)
	var music := OptionButton.new()
	music.name = "MusicFrequency"
	for choice in ["Often", "Sometimes", "Never"]:
		music.add_item(choice)
	music.item_selected.connect(
		func(i: int) -> void: Settings.set_music_frequency(Settings.MUSIC_FREQUENCIES[i])
	)
	_row(grid, "Music plays", music)
	return grid.get_parent()


func _controls_tab() -> Control:
	var grid := _tab("Controls")
	_row(
		grid,
		"Mouse sensitivity",
		_slider("Sensitivity", 0.2, 3.0, 0.05, Settings.set_mouse_sensitivity)
	)
	_row(
		grid,
		"Stick sensitivity",
		_slider("StickSensitivity", 0.2, 3.0, 0.05, Settings.set_stick_sensitivity)
	)
	var invert := CheckBox.new()
	invert.name = "InvertY"
	invert.toggled.connect(Settings.set_invert_y)
	_row(grid, "Invert Y", invert)
	var shake := CheckBox.new()
	shake.name = "CameraShake"
	shake.toggled.connect(Settings.set_camera_shake)
	_row(grid, "Camera shake", shake)
	_row(grid, "Run", _hold_or_toggle("SprintMode", Settings.set_sprint_toggle))
	_row(grid, "Rest", _hold_or_toggle("RestMode", Settings.set_rest_toggle))
	var heads := HBoxContainer.new()
	for title in ["Keyboard / mouse", "Gamepad"]:
		var head := Label.new()
		head.text = title
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heads.add_child(head)
	_row(grid, "", heads)
	for action: StringName in ACTION_NAMES:
		var pair := HBoxContainer.new()
		_binding_buttons[action] = _bind_button(pair, "Bind_" + String(action), action, false)
		_pad_buttons[action] = _bind_button(pair, "PadBind_" + String(action), action, true)
		_row(grid, ACTION_NAMES[action], pair)
	var restore := Button.new()
	restore.name = "RestoreDefaults"
	restore.text = "Restore defaults"
	restore.pressed.connect(
		func() -> void:
			Settings.restore_default_bindings()
			_refresh()
	)
	_row(grid, "", restore)
	return grid.get_parent()


func _interface_tab() -> Control:
	var grid := _tab("Interface")
	var size := OptionButton.new()
	size.name = "TextSize"
	for scale in UI_SCALES:
		size.add_item("%d %%" % roundi(scale * 100.0))
	size.item_selected.connect(func(i: int) -> void: Settings.set_ui_scale(UI_SCALES[i]))
	_row(grid, "Text size", size)
	var hints := CheckBox.new()
	hints.name = "ShowHints"
	hints.toggled.connect(func(on: bool) -> void: Settings.hints.enabled = on)
	_row(grid, "Show hints", hints)
	var again := Button.new()
	again.name = "TeachAgain"
	again.text = "Teach me again"
	again.pressed.connect(
		func() -> void:
			Settings.hints.reset()
			_status.text = "Hints will show again"
	)
	_row(grid, "", again)
	return grid.get_parent()


func _bind_button(parent: Control, node_name: String, action: StringName, pad: bool) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(150, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.pressed.connect(begin_capture.bind(action, pad))
	parent.add_child(b)
	return b


func _hold_or_toggle(node_name: String, on_change: Callable) -> OptionButton:
	var choice := OptionButton.new()
	choice.name = node_name
	choice.add_item("Hold")
	choice.add_item("Toggle")
	choice.item_selected.connect(func(i: int) -> void: on_change.call(i == 1))
	return choice


func _tab(title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.follow_focus = true
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	return grid


func _row(grid: GridContainer, text: String, field: Control) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(200, 0)
	grid.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)


func _slider(
	node_name: String, min_value: float, max_value: float, step: float, on_change: Callable
) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(240, 24)
	slider.value_changed.connect(on_change)
	return slider
