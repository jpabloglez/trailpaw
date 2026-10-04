## Player settings: graphics, audio volumes, mouse look and key bindings, persisted in
## [code]user://settings.cfg[/code] ([ConfigFile]). Changes apply at once; [method save_settings]
## writes them (the settings menu calls it when closed) and [method load_settings] reads them
## back on start.
##
## Key remapping covers the gameplay actions in [constant REMAPPABLE] (not the debug keys);
## bindings are stored by physical key or mouse button, a key already used by another action is
## refused, and [method restore_default_bindings] goes back to the project's InputMap.
## [br][br]
## Autoload name: [code]Settings[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node

## The graphics quality preset changed; systems depending on it (vegetation density, …)
## should apply [param preset].
signal quality_changed(preset: QualityPreset)
## The volume of audio bus [param bus] changed to [param linear] (0…1).
signal volume_changed(bus: StringName, linear: float)
## Any setting changed ([param key] names it, e.g. [code]&"fov"[/code]).
signal changed(key: StringName)

## Preset used until the player picks another.
const DEFAULT_QUALITY_PATH: String = "res://data/quality/medium.tres"
## Quality presets by id.
const QUALITY_PATHS: Dictionary[StringName, String] = {
	&"low": "res://data/quality/low.tres",
	&"medium": "res://data/quality/medium.tres",
	&"high": "res://data/quality/high.tres",
}
## Audio buses in [code]default_bus_layout.tres[/code] order: everything goes through Master;
## the others are the groups players can set apart.
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Ambience"]
## Gameplay actions the player may rebind (debug keys are fixed).
const REMAPPABLE: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"sprint",
	&"jump",
	&"interact",
	&"sniff",
	&"rest",
	&"camera_zoom_in",
	&"camera_zoom_out",
	&"map",
	&"pause",
]
## Where settings are kept (tests point it elsewhere).
const DEFAULT_PATH: String = "user://settings.cfg"
## Window sizes offered (windowed mode).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)
]

## Current graphics quality preset.
var quality: QualityPreset = preload(DEFAULT_QUALITY_PATH)
## Volume per bus, linear 0…1 (0 = muted).
var volumes: Dictionary[StringName, float] = {
	&"Master": 1.0, &"Music": 1.0, &"SFX": 1.0, &"Ambience": 1.0
}
## Fullscreen or windowed.
var fullscreen: bool = false
## Window size (windowed mode).
var resolution: Vector2i = Vector2i(1920, 1080)
## 3D render scale (0.5…1; lower is faster on weak GPUs).
var render_scale: float = 1.0
## Vertical sync.
var vsync: bool = true
## Camera field of view (degrees).
var fov: float = 70.0
## Mouse look speed multiplier (1 = the camera's tuned default).
var mouse_sensitivity: float = 1.0
## Invert vertical mouse look.
var invert_y: bool = false
## A subtle camera shake on hard landings.
var camera_shake: bool = true
## Where [method save_settings] and [method load_settings] work.
var config_path: String = DEFAULT_PATH


func _ready() -> void:
	load_settings()


## Sets the volume of [param bus] to [param linear] (0…1, clamped; 0 mutes) and applies it.
func set_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("Settings.set_volume: unknown bus '%s'" % bus)
		return
	var value := clampf(linear, 0.0, 1.0)
	volumes[bus] = value
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	volume_changed.emit(bus, value)
	changed.emit(&"volume")


## Volume of [param bus] (linear 0…1).
func volume(bus: StringName) -> float:
	return volumes.get(bus, 1.0)


## Switches to [param preset] and notifies listeners (no-op if it is already active).
func set_quality(preset: QualityPreset) -> void:
	if preset == quality:
		return
	quality = preset
	quality_changed.emit(preset)
	changed.emit(&"quality")


## Fullscreen on or off.
func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window()
	changed.emit(&"fullscreen")


## Window size in windowed mode.
func set_resolution(value: Vector2i) -> void:
	resolution = value
	_apply_window()
	changed.emit(&"resolution")


## 3D render scale (clamped to 0.5…1).
func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	_apply_render_scale()
	changed.emit(&"render_scale")


## Vertical sync on or off.
func set_vsync(value: bool) -> void:
	vsync = value
	_apply_vsync()
	changed.emit(&"vsync")


## Field of view (clamped to 50…100°); the camera follows [signal changed].
func set_fov(value: float) -> void:
	fov = clampf(value, 50.0, 100.0)
	changed.emit(&"fov")


## Mouse look speed multiplier (clamped to 0.2…3).
func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.2, 3.0)
	changed.emit(&"mouse_sensitivity")


## Invert vertical mouse look.
func set_invert_y(value: bool) -> void:
	invert_y = value
	changed.emit(&"invert_y")


## Camera shake on hard landings on or off.
func set_camera_shake(value: bool) -> void:
	camera_shake = value
	changed.emit(&"camera_shake")


## Binds [param action] to [param event] (a key, by physical keycode, or a mouse button) in
## place of its current bindings. Returns the action that already uses it (and changes nothing),
## or an empty name on success.
func rebind(action: StringName, event: InputEvent) -> StringName:
	var normal := normalise_event(event)
	if normal == null or not REMAPPABLE.has(action):
		return &"?"
	for other in REMAPPABLE:
		if other != action and InputMap.action_has_event(other, normal):
			return other
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, normal)
	changed.emit(&"bindings")
	return &""


## Restores every remappable action to the project's default bindings.
func restore_default_bindings() -> void:
	for action in REMAPPABLE:
		InputMap.action_erase_events(action)
		var defaults: Dictionary = ProjectSettings.get_setting("input/" + String(action), {})
		for event: InputEvent in defaults.get("events", []):
			InputMap.action_add_event(action, event)
	changed.emit(&"bindings")


## Human-readable binding of [param action] (e.g. "W", "Mouse Wheel Up").
func binding_text(action: StringName) -> String:
	var parts := PackedStringArray()
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			parts.append(OS.get_keycode_string(key.physical_keycode))
			continue
		var mouse := event as InputEventMouseButton
		if mouse != null:
			parts.append(_mouse_name(mouse.button_index))
	return ", ".join(parts)


## A clean copy of [param event] for binding (physical key or mouse button), or null.
static func normalise_event(event: InputEvent) -> InputEvent:
	var key := event as InputEventKey
	if key != null:
		var copy := InputEventKey.new()
		copy.physical_keycode = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return copy if copy.physical_keycode != 0 else null
	var mouse := event as InputEventMouseButton
	if mouse != null:
		var copy := InputEventMouseButton.new()
		copy.button_index = mouse.button_index
		return copy
	return null


## Writes every setting to [member config_path].
func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", String(quality.id))
	config.set_value("graphics", "fullscreen", fullscreen)
	config.set_value("graphics", "resolution", [resolution.x, resolution.y])
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "vsync", vsync)
	config.set_value("graphics", "fov", fov)
	for bus in BUSES:
		config.set_value("audio", String(bus), volume(bus))
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "camera_shake", camera_shake)
	for action in REMAPPABLE:
		config.set_value("bindings", String(action), _serialise(action))
	return config.save(config_path)


## Reads the settings from [member config_path] (missing or unreadable values keep their
## defaults) and applies them.
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		_apply_all()
		return
	var quality_id := StringName(str(config.get_value("graphics", "quality", "medium")))
	if QUALITY_PATHS.has(quality_id):
		quality = load(QUALITY_PATHS[quality_id])
	fullscreen = bool(config.get_value("graphics", "fullscreen", fullscreen))
	var size: Array = config.get_value("graphics", "resolution", [resolution.x, resolution.y])
	if size.size() == 2:
		resolution = Vector2i(int(size[0]), int(size[1]))
	render_scale = clampf(float(config.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0)
	vsync = bool(config.get_value("graphics", "vsync", vsync))
	fov = clampf(float(config.get_value("graphics", "fov", fov)), 50.0, 100.0)
	for bus in BUSES:
		volumes[bus] = clampf(float(config.get_value("audio", String(bus), 1.0)), 0.0, 1.0)
	mouse_sensitivity = clampf(
		float(config.get_value("controls", "mouse_sensitivity", 1.0)), 0.2, 3.0
	)
	invert_y = bool(config.get_value("controls", "invert_y", false))
	camera_shake = bool(config.get_value("controls", "camera_shake", true))
	for action in REMAPPABLE:
		var stored: Array = config.get_value("bindings", String(action), [])
		if not stored.is_empty():
			_deserialise(action, stored)
	_apply_all()


func _apply_all() -> void:
	for bus in BUSES:
		set_volume(bus, volume(bus))
	_apply_window()
	_apply_render_scale()
	_apply_vsync()
	quality_changed.emit(quality)
	changed.emit(&"all")


func _has_window() -> bool:
	return DisplayServer.get_name() != "headless"


func _apply_window() -> void:
	if not _has_window():
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)


func _apply_render_scale() -> void:
	if is_inside_tree():
		get_viewport().scaling_3d_scale = render_scale


func _apply_vsync() -> void:
	if not _has_window():
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


func _serialise(action: StringName) -> Array:
	var out: Array = []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			out.append({"key": key.physical_keycode})
		var mouse := event as InputEventMouseButton
		if mouse != null:
			out.append({"mouse": mouse.button_index})
	return out


func _deserialise(action: StringName, stored: Array) -> void:
	var events: Array[InputEvent] = []
	for entry: Variant in stored:
		if not entry is Dictionary:
			continue
		var d: Dictionary = entry
		if d.has("key"):
			var key := InputEventKey.new()
			key.physical_keycode = int(d["key"]) as Key
			events.append(key)
		elif d.has("mouse"):
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(d["mouse"]) as MouseButton
			events.append(mouse)
	if events.is_empty():
		return
	InputMap.action_erase_events(action)
	for event in events:
		InputMap.action_add_event(action, event)


static func _mouse_name(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "Left Click"
		MOUSE_BUTTON_RIGHT:
			return "Right Click"
		MOUSE_BUTTON_MIDDLE:
			return "Middle Click"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
	return "Mouse %d" % button
