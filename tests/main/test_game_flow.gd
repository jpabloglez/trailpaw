## Tests for the game flow: main menu over the attract world, new game (seed, replacing a
## saved game), continue, pause menu, saving when leaving and closing.
extends GdUnitTestSuite

const MAIN_SCENE: String = "res://scenes/main/main.tscn"
const TEST_DIR: String = "user://test_flow_saves"
const MAX_FRAMES: int = 1500

var _saved_dir: String
var _flow: GameFlow


func before_test() -> void:
	_saved_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.erase()


func after_test() -> void:
	get_tree().paused = false
	if _flow != null and is_instance_valid(_flow):
		_flow.free()
	SaveSystem.erase()
	SaveSystem.save_dir = _saved_dir
	FloatingOrigin.reset()
	get_tree().auto_accept_quit = true


func _start() -> GameFlow:
	_flow = load(MAIN_SCENE).instantiate() as GameFlow
	_flow.suppress_quit = true
	add_child(_flow)
	return _flow


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# Waits for a menu-driven switch: fade to black, swap the world, a couple of frames.
func _settle() -> void:
	await get_tree().create_timer(ScreenFade.SECONDS + 0.1).timeout
	await _frames(2)


func _until(condition: Callable) -> bool:
	for i in MAX_FRAMES:
		await get_tree().process_frame
		if condition.call():
			return true
	return false


func _landed() -> bool:
	return await _until(
		func() -> bool: return _flow.world() != null and not _flow.world().spawner.is_parked()
	)


func _save_with_seed(world_seed: int) -> void:
	var save := SaveData.new()
	save.world_seed = world_seed
	save.player_position = Vector3(500.0, 20.0, -300.0)
	save.game_minutes = 1000.0
	SaveSystem.write(save)


func test_starts_at_the_menu_over_a_world_that_never_saves() -> void:
	var flow := _start()
	assert_object(flow.menu()).is_not_null()
	assert_bool(flow.is_playing()).is_false()
	assert_bool(flow.world().attract_mode).is_true()
	assert_bool(flow.world().animal.visible).is_false()
	assert_object(flow.world().attract_camera()).is_not_null()
	await _frames(1)
	for child in flow.world().get_children():
		assert_bool(child is CanvasLayer).override_failure_message(child.name).is_false()
	assert_bool(flow.world().attract_camera().current).is_true()
	assert_int(flow.world().attract_camera().physics_interpolation_mode).is_equal(
		Node.PHYSICS_INTERPOLATION_MODE_OFF
	)
	assert_bool(flow.menu().button("Continue").visible).is_false()  # nothing saved yet
	await _frames(5)
	assert_bool(flow.world().save_now()).is_false()


func test_continue_shows_only_with_a_saved_game_and_the_menu_world_uses_its_seed() -> void:
	_save_with_seed(31337)
	var flow := _start()
	assert_bool(flow.menu().button("Continue").visible).is_true()
	assert_int(GameState.world_seed).is_equal(31337)


func test_a_new_game_uses_the_typed_seed() -> void:
	var flow := _start()
	flow.menu().show_new_game()
	assert_int(flow.menu().seed_value()).is_greater_equal(0)  # a random seed is offered
	flow.menu().seed_field().text = "4242"
	flow.menu().button("Start").pressed.emit()
	await _settle()
	assert_bool(flow.is_playing()).is_true()
	assert_object(flow.menu()).is_null()
	assert_int(GameState.world_seed).is_equal(4242)
	assert_bool(flow.world().attract_mode).is_false()


func test_the_seed_field_keeps_digits_only_and_rejects_nonsense() -> void:
	var flow := _start()
	flow.menu().show_new_game()
	var field := flow.menu().seed_field()
	field.text = "12a3"
	field.text_changed.emit(field.text)
	assert_str(field.text).is_equal("123")
	field.text = ""
	assert_int(flow.menu().seed_value()).is_equal(-1)
	flow.menu().start_new_game()
	await _settle()
	assert_bool(flow.is_playing()).is_false()


func test_a_new_game_asks_before_replacing_the_saved_one() -> void:
	_save_with_seed(1)
	var flow := _start()
	flow.menu().show_new_game()
	flow.menu().seed_field().text = "99"
	flow.menu().button("Start").pressed.emit()
	await _settle()
	assert_str(flow.menu().page()).is_equal("confirm")
	assert_bool(flow.is_playing()).is_false()
	flow.menu().button("Keep").pressed.emit()
	assert_str(flow.menu().page()).is_equal("main")
	assert_bool(SaveSystem.exists()).is_true()
	flow.menu().show_new_game()
	flow.menu().seed_field().text = "99"
	flow.menu().start_new_game()
	flow.menu().button("Replace").pressed.emit()
	await _settle()
	assert_bool(flow.is_playing()).is_true()
	assert_int(GameState.world_seed).is_equal(99)
	assert_bool(SaveSystem.exists()).is_false()  # the old game is gone


func test_continue_resumes_the_saved_game() -> void:
	_save_with_seed(2024)
	var flow := _start()
	flow.menu().button("Continue").pressed.emit()
	await _settle()
	assert_bool(flow.is_playing()).is_true()
	assert_int(GameState.world_seed).is_equal(2024)
	assert_float(GameState.game_minutes).is_between(1000.0, 1001.0)
	var absolute: Vector3 = GameState.absolute_position(flow.world().animal.global_position)
	assert_float(absolute.x).is_equal_approx(500.0, 0.5)


func test_the_pause_menu_stops_the_world_and_shows_the_seed() -> void:
	var flow := _start()
	flow.start_new_game(808)
	assert_bool(await _landed()).is_true()
	var pause := flow.pause_menu()
	var press := InputEventAction.new()
	press.action = &"pause"
	press.pressed = true
	Input.parse_input_event(press)
	await _settle()
	assert_bool(pause.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(pause.seed_text()).contains("808")
	pause.button("Resume").pressed.emit()
	assert_bool(get_tree().paused).is_false()
	assert_bool(pause.visible).is_false()


func test_pause_save_writes_the_game() -> void:
	var flow := _start()
	flow.start_new_game(11)
	assert_bool(await _landed()).is_true()
	flow.pause_menu().open()
	flow.pause_menu().button("Save").pressed.emit()
	assert_bool(SaveSystem.exists()).is_true()
	assert_int(SaveSystem.read().world_seed).is_equal(11)


func test_going_back_to_the_menu_saves_then_continue_returns_there() -> void:
	var flow := _start()
	flow.start_new_game(5150)
	assert_bool(await _landed()).is_true()
	flow.world().animal.global_position.x += 7.0
	var where: Vector3 = GameState.absolute_position(flow.world().animal.global_position)
	flow.pause_menu().open()
	flow.pause_menu().button("MainMenu").pressed.emit()
	await _settle()
	assert_object(flow.menu()).is_not_null()
	assert_bool(get_tree().paused).is_false()
	assert_bool(SaveSystem.exists()).is_true()
	flow.menu().button("Continue").pressed.emit()
	await _settle()
	var back: Vector3 = GameState.absolute_position(flow.world().animal.global_position)
	assert_float(back.x).is_equal_approx(where.x, 0.5)
	assert_float(back.z).is_equal_approx(where.z, 0.5)


func test_closing_the_window_saves_the_game() -> void:
	var flow := _start()
	flow.start_new_game(77)
	assert_bool(await _landed()).is_true()
	var quit: Array[int] = [0]
	flow.quitting.connect(func() -> void: quit[0] += 1)
	flow.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(quit[0]).is_equal(1)
	assert_bool(SaveSystem.exists()).is_true()
	assert_int(SaveSystem.read().world_seed).is_equal(77)


func test_quitting_from_the_menu_does_not_save() -> void:
	var flow := _start()
	flow.menu().button("Quit").pressed.emit()
	assert_bool(SaveSystem.exists()).is_false()


func test_the_world_is_swapped_behind_a_black_screen() -> void:
	var flow := _start()
	var covered_when_added: Array[float] = []
	flow.child_entered_tree.connect(
		func(node: Node) -> void:
			if node is WorldController:
				covered_when_added.append(flow.screen_fade().opacity())
	)
	flow.menu().show_new_game()
	flow.menu().button("Start").pressed.emit()
	await _frames(1)
	assert_float(flow.screen_fade().opacity()).is_less(1.0)  # still fading out
	await _settle()
	assert_array(covered_when_added).has_size(1)
	assert_float(covered_when_added[0]).is_equal_approx(1.0, 0.01)
	assert_bool(flow.is_playing()).is_true()
	await get_tree().create_timer(ScreenFade.SECONDS + 0.1).timeout
	assert_float(flow.screen_fade().opacity()).is_equal_approx(0.0, 0.01)  # and back
