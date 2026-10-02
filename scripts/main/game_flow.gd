class_name GameFlow
extends Node
## The game's entry point ([code]main.tscn[/code]): the main menu over an attract-mode world,
## then the game itself, with the pause menu and the map on top. It saves when going back to
## the menu, when quitting and when the window is closed, so a game can be left anywhere and
## continued exactly there.
##
## Switching worlds happens deferred and frees the old one before adding the new one, so the
## old world's clean-up (floating origin) never undoes the new one's set-up.

## Emitted right before the game quits (after saving).
signal quitting

## The playable world.
@export var world_scene: PackedScene

## Do not actually quit (tests).
var suppress_quit: bool = false

var _world: WorldController
var _menu: MainMenu
var _pause: PauseMenu
var _settings: SettingsMenu
var _map: MapScreen
var _playing: bool = false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)
	_pause.save_requested.connect(_on_save_requested)
	_pause.main_menu_requested.connect(func() -> void: _go.call_deferred(&"menu"))
	_pause.quit_requested.connect(quit_game)
	_settings = SettingsMenu.new()
	_settings.name = "SettingsMenu"
	add_child(_settings)
	_pause.settings_requested.connect(_open_settings)
	_settings.closed.connect(_on_settings_closed)
	_map = MapScreen.new()
	_map.name = "MapScreen"
	add_child(_map)
	_pause.map_requested.connect(_open_map)
	show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## Shows the main menu over an attract-mode world (the saved game's seed, or a random one).
func show_menu() -> void:
	_playing = false
	_pause.enabled = false
	_pause.close()
	_map.enabled = false
	_map.close()
	_map.world = null
	var saved := SaveSystem.read() if SaveSystem.exists() else null
	var world := world_scene.instantiate() as WorldController
	world.attract_mode = true
	world.world_seed = saved.world_seed if saved != null else randi() % 100000
	_replace_world(world)
	_menu = MainMenu.new()
	_menu.name = "MainMenu"
	add_child(_menu)
	_menu.continue_requested.connect(func() -> void: _go.call_deferred(&"continue"))
	_menu.new_game_requested.connect(func(s: int) -> void: _go.call_deferred(&"new", s))
	_menu.quit_requested.connect(quit_game)
	_menu.settings_requested.connect(_open_settings)


## Starts a new game with [param world_seed], replacing any saved game.
func start_new_game(world_seed: int) -> void:
	SaveSystem.erase()
	var world := world_scene.instantiate() as WorldController
	world.world_seed = world_seed
	_play(world)


## Continues the saved game (back to the menu if it cannot be read).
func continue_game() -> void:
	var saved := SaveSystem.read()
	if saved == null:
		push_warning("GameFlow: cannot continue: %s" % SaveSystem.last_error)
		show_menu()
		return
	var world := world_scene.instantiate() as WorldController
	world.pending_save = saved
	_play(world)


## Saves (when playing) and quits.
func quit_game() -> void:
	if _playing and _world != null:
		get_tree().paused = false
		_world.save_now()
	quitting.emit()
	if not suppress_quit:
		get_tree().quit()


## The current world (game or attract), or null.
func world() -> WorldController:
	return _world


## The main menu while it shows, or null.
func menu() -> MainMenu:
	return _menu


## The pause menu.
func pause_menu() -> PauseMenu:
	return _pause


## The settings menu.
func settings_menu() -> SettingsMenu:
	return _settings


## The map screen.
func map_screen() -> MapScreen:
	return _map


## Whether a game is being played (not the menu).
func is_playing() -> bool:
	return _playing


func _go(where: StringName, world_seed: int = 0) -> void:
	match where:
		&"menu":
			if _playing and _world != null:
				get_tree().paused = false
				_world.save_now()
			show_menu()
		&"continue":
			continue_game()
		&"new":
			start_new_game(world_seed)


func _play(world: WorldController) -> void:
	if _menu != null:
		_menu.free()
		_menu = null
	GameState.game_minutes = GameState.CLOCK.start_minutes
	GameState.current_biome = &""
	_replace_world(world)
	_playing = true
	_pause.enabled = true
	_map.world = world
	_map.enabled = true


func _replace_world(world: WorldController) -> void:
	get_tree().paused = false
	if _menu != null:
		_menu.free()
		_menu = null
	if _world != null:
		_world.free()  # now, so its clean-up runs before the new world's set-up
	_world = world
	add_child(world)
	move_child(world, 0)


func _on_save_requested() -> void:
	if _world != null and _world.save_now():
		_pause.show_saved()


func _open_map() -> void:
	_pause.close()
	_map.open()


func _open_settings() -> void:
	_pause.visible = false
	if _menu != null:
		_menu.visible = false
	_settings.open()


func _on_settings_closed() -> void:
	if _menu != null:
		_menu.visible = true
	elif _playing and get_tree().paused:
		_pause.visible = true
