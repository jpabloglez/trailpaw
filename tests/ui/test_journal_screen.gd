## Tests for the journal screen in the game flow: J opens it paused and closes it, Esc closes it,
## the pause menu opens it, it is off in the main menu; the counter and the cards follow the
## journal (met animals show their name and line, the others a silhouette and where they live);
## the action is remappable; and the hint after the first animal met.
extends GdUnitTestSuite

const MAIN_SCENE: String = "res://scenes/main/main.tscn"
const TEST_DIR: String = "user://test_journal_saves"
const MAX_FRAMES: int = 1500
const JOURNAL: JournalSettings = preload("res://data/journal/journal.tres")

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


func _until(condition: Callable) -> bool:
	for i in MAX_FRAMES:
		await get_tree().process_frame
		if condition.call():
			return true
	return false


func _playing() -> GameFlow:
	_flow = load(MAIN_SCENE).instantiate() as GameFlow
	_flow.suppress_quit = true
	add_child(_flow)
	_flow.start_new_game(12345)
	var landed := await _until(
		func() -> bool: return _flow.world() != null and not _flow.world().spawner.is_parked()
	)
	assert_bool(landed).is_true()
	_flow.world().animal.get_node("%PlayerInput").set_physics_process(false)
	return _flow


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func test_j_opens_the_journal_paused_and_closes_it() -> void:
	var flow := await _playing()
	var journal := flow.journal_screen()
	await _press(&"journal")
	assert_bool(journal.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	await _press(&"journal")
	assert_bool(journal.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	await _press(&"journal")
	await _press(&"pause")  # Esc closes it (and does not open the pause menu)
	assert_bool(journal.visible).is_false()
	assert_bool(flow.pause_menu().visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_cards_follow_the_journal() -> void:
	var flow := await _playing()
	var met := flow.world().encounters.journal
	met.clear()
	met.discover(&"frog", 600.0, &"wetland")
	met.discover(&"deer", 700.0, &"forest")
	var journal := flow.journal_screen()
	journal.open()
	assert_str(journal.counter_text()).is_equal("2 / %d animals" % JOURNAL.entries.size())
	var frog := journal.card_texts(&"frog")
	assert_str(frog.name).is_equal("Frog")
	assert_str(frog.blurb).is_equal(JOURNAL.entry(&"frog").blurb)
	assert_str(frog.biomes).contains("Wetland")
	assert_bool(frog.silhouette).is_false()
	var heron := journal.card_texts(&"heron")  # not met yet: a silhouette, and where to look
	assert_str(heron.name).is_equal("???")
	assert_str(heron.blurb).is_equal("")
	assert_str(heron.biomes).is_equal("Lives in: River Valley, Wetland")
	assert_bool(heron.silhouette).is_true()
	assert_bool(await _until(func() -> bool: return not journal.is_loading())).is_true()
	for entry in JOURNAL.entries:  # every portrait rendered (blank headless) and kept
		assert_object(PortraitStudio.cached(entry.id)).is_not_null()
	journal.close()


func test_the_pause_menu_opens_it_and_the_main_menu_does_not() -> void:
	var flow := await _playing()
	await _press(&"pause")
	flow.pause_menu().journal_requested.emit()
	await get_tree().process_frame
	assert_bool(flow.journal_screen().visible).is_true()
	assert_bool(flow.pause_menu().visible).is_false()
	flow.journal_screen().close()
	flow.show_menu()
	await get_tree().process_frame
	await _press(&"journal")
	assert_bool(flow.journal_screen().visible).is_false()  # nothing to show from the menu


func test_the_journal_key_is_remappable_and_hinted_after_the_first_animal() -> void:
	assert_bool(Settings.REMAPPABLE.has(&"journal")).is_true()
	assert_bool(HintDirector.ORDER.has(&"journal")).is_true()
	var hints: HintSettings = load("res://data/ui/hints.tres")
	assert_str(hints.texts[&"journal"]).contains("{journal}")
