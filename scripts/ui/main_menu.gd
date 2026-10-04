class_name MainMenu
extends CanvasLayer
## Title screen over the living world: Continue (only when a game is saved), New game (a random
## seed that can be edited, and a confirmation before replacing the saved game), Settings and
## Quit. Built in code.

## Continue the saved game.
signal continue_requested
## Start a new game with [param world_seed] (the saved game, if any, was confirmed away).
signal new_game_requested(world_seed: int)
## Open the settings.
signal settings_requested
## Leave the game.
signal quit_requested

## Largest seed offered (any non-negative 32-bit integer is accepted).
const MAX_SEED: int = 2147483647

var _root: Control
var _main: VBoxContainer
var _new_game: VBoxContainer
var _confirm: VBoxContainer
var _seed: LineEdit
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 50
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var title := MenuStyle.label("Trailpaw", 84, "Title")
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position.y = 70
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(title)
	_build_main()
	_build_new_game()
	_build_confirm()
	_rng.randomize()
	show_main()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Back to the first page (Continue shows only when a game is saved).
func show_main() -> void:
	(_main.get_node("Continue") as Button).visible = SaveSystem.exists()
	_show(_main)


## The New game page, with a fresh random seed.
func show_new_game() -> void:
	_seed.text = str(_rng.randi_range(0, MAX_SEED))
	_show(_new_game)


## Starts a new game with the typed seed, asking first if it would replace a saved game.
func start_new_game() -> void:
	var value := seed_value()
	if value < 0:
		return
	if SaveSystem.exists():
		_show(_confirm)
	else:
		new_game_requested.emit(value)


## The typed seed, or −1 when it is not a valid number.
func seed_value() -> int:
	var text := _seed.text.strip_edges()
	if text.is_empty() or not text.is_valid_int() or int(text) < 0 or int(text) > MAX_SEED:
		return -1
	return int(text)


## The seed field (tests and tools).
func seed_field() -> LineEdit:
	return _seed


## The button named [param node_name] on any page (tests and tools).
func button(node_name: String) -> Button:
	return _root.find_child(node_name, true, false) as Button


## Which page shows: [code]"main"[/code], [code]"new_game"[/code] or [code]"confirm"[/code].
func page() -> String:
	if _new_game.get_parent().get_parent().visible:
		return "new_game"
	if _confirm.get_parent().get_parent().visible:
		return "confirm"
	return "main"


func _build_main() -> void:
	_main = MenuStyle.centred_box(_root, "MainPage")
	for entry: Array in [
		["Continue", "Continue", continue_requested.emit],
		["New game", "NewGame", show_new_game],
		["Settings", "Settings", settings_requested.emit],
		["Quit", "Quit", quit_requested.emit],
	]:
		var b := MenuStyle.button(entry[0], entry[1])
		b.pressed.connect(entry[2])
		_main.add_child(b)


func _build_new_game() -> void:
	_new_game = MenuStyle.centred_box(_root, "NewGamePage")
	_new_game.add_child(MenuStyle.label("World seed", 26))
	_seed = LineEdit.new()
	_seed.name = "Seed"
	_seed.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed.add_theme_font_size_override(&"font_size", 26)
	_seed.max_length = 10
	_seed.text_changed.connect(_keep_digits)
	_seed.text_submitted.connect(func(_text: String) -> void: start_new_game())
	_new_game.add_child(_seed)
	var start := MenuStyle.button("Start", "Start")
	start.pressed.connect(start_new_game)
	_new_game.add_child(start)
	var back := MenuStyle.button("Back", "Back")
	back.pressed.connect(show_main)
	_new_game.add_child(back)


func _build_confirm() -> void:
	_confirm = MenuStyle.centred_box(_root, "ConfirmPage")
	_confirm.add_child(MenuStyle.label("Start over? Your current game will be replaced.", 22))
	var replace := MenuStyle.button("Replace it", "Replace")
	replace.pressed.connect(func() -> void: new_game_requested.emit(seed_value()))
	_confirm.add_child(replace)
	var keep := MenuStyle.button("Keep my game", "Keep")
	keep.pressed.connect(show_main)
	_confirm.add_child(keep)


func _show(box: VBoxContainer) -> void:
	for page_box in [_main, _new_game, _confirm]:
		(page_box.get_parent().get_parent() as Control).visible = page_box == box
	MenuStyle.fade_in(box.get_parent().get_parent() as Control)


func _keep_digits(text: String) -> void:
	var digits := ""
	for c in text:
		if c >= "0" and c <= "9":
			digits += c
	if digits != text:
		var caret := _seed.caret_column
		_seed.text = digits
		_seed.caret_column = mini(caret, digits.length())
