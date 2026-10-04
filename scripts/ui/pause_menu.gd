class_name PauseMenu
extends CanvasLayer
## In-game pause (the [code]pause[/code] action, Esc): the world stops
## ([code]get_tree().paused[/code]) and this menu — which keeps running — offers Resume, Save,
## Map, Settings, Main menu and Quit, and shows the world seed so it can be shared. Built in code.

## Save now (the menu shows "Saved" when [method show_saved] is called).
signal save_requested
## Open the map.
signal map_requested
## Open the settings.
signal settings_requested
## Save and go back to the main menu.
signal main_menu_requested
## Save and leave the game.
signal quit_requested

## Seconds the "Saved" note stays.
const SAVED_NOTE_SECONDS: float = 2.0

## Whether Esc opens the menu (off while in the main menu).
var enabled: bool = false

var _root: Control
var _seed: Label
var _note: Label
var _note_left: float = 0.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var box := MenuStyle.centred_box(_root, "PausePage")
	box.add_child(MenuStyle.label("Paused", 40))
	for entry: Array in [
		["Resume", "Resume", close],
		["Save", "Save", save_requested.emit],
		["Map", "Map", map_requested.emit],
		["Settings", "Settings", settings_requested.emit],
		["Main menu", "MainMenu", main_menu_requested.emit],
		["Quit", "Quit", quit_requested.emit],
	]:
		var b := MenuStyle.button(entry[0], entry[1])
		b.pressed.connect(entry[2])
		box.add_child(b)
	_note = MenuStyle.label("Saved", 20, "Note")
	_note.modulate.a = 0.0
	box.add_child(_note)
	_seed = MenuStyle.label("", 18, "Seed")
	box.add_child(_seed)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if enabled and event.is_action_pressed(&"pause"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _note_left > 0.0:
		_note_left -= delta
		_note.modulate.a = clampf(_note_left / 0.5, 0.0, 1.0)


## Pauses the world and shows the menu.
func open() -> void:
	_seed.text = "World seed %d" % GameState.world_seed
	visible = true
	MenuStyle.fade_in(_root)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Hides the menu and resumes the world.
func close() -> void:
	visible = false
	get_tree().paused = false


## Shows the "Saved" note for a moment.
func show_saved() -> void:
	_note_left = SAVED_NOTE_SECONDS
	_note.modulate.a = 1.0


## The button named [param node_name] (tests and tools).
func button(node_name: String) -> Button:
	return _root.find_child(node_name, true, false) as Button


## The seed text shown.
func seed_text() -> String:
	return _seed.text
